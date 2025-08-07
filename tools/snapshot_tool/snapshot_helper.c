#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <libgen.h> // For dirname

#define MAX_PATH 2048
#define MAX_LINE 4096
#define HASH_TABLE_SIZE 99989 // A prime number for better distribution

// Represents a single file entry in the snapshot
typedef struct {
    char path[MAX_PATH];
    long size;
    time_t mtime;
    char hash[33]; // MD5 hash
    int seen;      // Flag to track if the entry was found in the new snapshot
} FileEntry;

// A node in the hash table's linked list
typedef struct Node {
    FileEntry entry;
    struct Node* next;
} Node;

// Simple string hash function (djb2)
unsigned long hash_string(const char* str) {
    unsigned long hash = 5381;
    int c;
    while ((c = (unsigned char)*str++)) {
        hash = ((hash << 5) + hash) + c; // hash * 33 + c
    }
    return hash;
}

// Creates a new hash table
Node** create_hash_table() {
    return (Node**)calloc(HASH_TABLE_SIZE, sizeof(Node*));
}

// Inserts a file entry into the hash table
void insert_entry(Node** table, FileEntry entry) {
    unsigned long index = hash_string(entry.path) % HASH_TABLE_SIZE;
    Node* new_node = (Node*)malloc(sizeof(Node));
    if (!new_node) {
        perror("Failed to allocate memory for hash node");
        exit(EXIT_FAILURE);
    }
    new_node->entry = entry;
    new_node->next = table[index];
    table[index] = new_node;
}

// Finds a file entry in the hash table by its path
FileEntry* find_entry(Node** table, const char* path) {
    unsigned long index = hash_string(path) % HASH_TABLE_SIZE;
    Node* current = table[index];
    while (current != NULL) {
        if (strcmp(current->entry.path, path) == 0) {
            return &current->entry;
        }
        current = current->next;
    }
    return NULL;
}

// Parses a line from the manifest file into a FileEntry struct
int parse_line(char* line, FileEntry* entry) {
    line[strcspn(line, "\n")] = 0; // Strip newline
    if (strlen(line) == 0) return 0; // Skip empty lines

    char* parts[4];
    int count = 0;
    // Use a mutable copy for strtok
    char mutable_line[MAX_LINE];
    strncpy(mutable_line, line, MAX_LINE);
    mutable_line[MAX_LINE -1] = '\0';
    
    char* token = strtok(mutable_line, ";");
    while (token != NULL && count < 4) {
        parts[count++] = token;
        token = strtok(NULL, ";");
    }

    if (count != 4) {
        return 0; // Malformed line
    }

    strncpy(entry->path, parts[0], MAX_PATH - 1);
    entry->path[MAX_PATH - 1] = '\0';
    entry->size = atol(parts[1]);
    entry->mtime = atol(parts[2]);
    strncpy(entry->hash, parts[3], 33 - 1);
    entry->hash[33 - 1] = '\0';
    
    entry->seen = 0;
    return 1;
}

// Loads a snapshot file into the provided hash table
void load_snapshot(const char* filename, Node** table, const char* base_dir_filter) {
    FILE* fp = fopen(filename, "r");
    if (!fp) {
        fprintf(stderr, "Error: Could not open snapshot file: %s\n", filename);
        return;
    }

    char line_buffer[MAX_LINE];
    size_t filter_len = strlen(base_dir_filter);

    while (fgets(line_buffer, sizeof(line_buffer), fp)) {
        if (strncmp(line_buffer, base_dir_filter, filter_len) != 0) {
            continue;
        }

        FileEntry entry;
        if (parse_line(line_buffer, &entry)) {
            insert_entry(table, entry);
        }
    }
    fclose(fp);
}

// Frees all memory associated with the hash table
void free_hash_table(Node** table) {
    if (!table) return;
    for (int i = 0; i < HASH_TABLE_SIZE; i++) {
        Node* current = table[i];
        while (current != NULL) {
            Node* to_free = current;
            current = current->next;
            free(to_free);
        }
    }
    free(table);
}

int main(int argc, char* argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <old_manifest> <new_manifest> <base_dir_filter>\n", argv[0]);
        return 1;
    }

    const char* old_manifest_path = argv[1];
    const char* new_manifest_path = argv[2];
    const char* base_dir_filter = argv[3];

    Node** old_table = create_hash_table();
    load_snapshot(old_manifest_path, old_table, base_dir_filter);

    FILE* fp_new = fopen(new_manifest_path, "r");
    if (!fp_new) {
        fprintf(stderr, "Error opening new manifest: %s\n", new_manifest_path);
        free_hash_table(old_table);
        return 1;
    }

    // --- First Pass: Detect New/Modified ---
    char line_buffer[MAX_LINE];
    while (fgets(line_buffer, sizeof(line_buffer), fp_new)) {
        FileEntry new_entry;
        if (!parse_line(line_buffer, &new_entry)) continue;
        
        FileEntry* old_entry = find_entry(old_table, new_entry.path);

        if (old_entry == NULL) {
            printf("[+] %s\n", new_entry.path);
        } else {
            old_entry->seen = 1;
            if (old_entry->size != new_entry.size || old_entry->mtime != new_entry.mtime || strcmp(old_entry->hash, new_entry.hash) != 0) {
                printf("[M] %s\n", new_entry.path);
            }
        }
    }
    rewind(fp_new); // Reset file pointer for the second pass

    // --- Second Pass: Detect Deleted ---
    for (int i = 0; i < HASH_TABLE_SIZE; i++) {
        Node* current = old_table[i];
        while (current != NULL) {
            if (!current->entry.seen) {
                printf("[-] %s\n", current->entry.path);
            }
            current = current->next;
        }
    }
    
    // --- Final Pass: Output for Piping ---
    printf("---\n");
    while (fgets(line_buffer, sizeof(line_buffer), fp_new)) {
        FileEntry new_entry;
        if (!parse_line(line_buffer, &new_entry)) continue;
        
        FileEntry* old_entry = find_entry(old_table, new_entry.path);

        if (old_entry == NULL) {
            printf("%s\n", new_entry.path); // New file
        } else {
             if (old_entry->size != new_entry.size || old_entry->mtime != new_entry.mtime || strcmp(old_entry->hash, new_entry.hash) != 0) {
                printf("%s\n", new_entry.path); // Modified file
            }
        }
    }
    
    fclose(fp_new);
    free_hash_table(old_table);

    return 0;
}
