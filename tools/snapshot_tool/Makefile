# Makefile for the snapshot_helper tool

# Compiler and flags
CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -O2
LDFLAGS =

# Source and object files
SRCS = snapshot_helper.c
OBJS = $(SRCS:.c=.o)
TARGET = snapshot_helper

# Default target
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $(TARGET) $(OBJS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Clean up build files
clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
