.PHONY: clean help

CC = gcc
CFLAGS = -g -I. -Wall -Werror


SRC_DIR = src
OBJ_DIR = obj
BIN_DIR = bin


SRC = $(wildcard $(SRC_DIR)/*.c)
OBJ = $(SRC:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o)

TARGET = $(BIN_DIR)/client $(BIN_DIR)/server

all: $(TARGET)

$(TARGET): $(OBJ)
	@mkdir -p $(BIN_DIR)
	$(CC) $(OBJ) -o $@

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

help:
	@echo "Available targets:"
	@echo "  help        - Show this help message"
	@echo "  clean       - Remove build artifacts"
	@echo "  submission  - Create zip to submit"
	@echo "  all         - Build the program (default target)"

submission:
	zip -r submission.zip $(SRC_DIR) Makefile README.md ASSIGNMENT.md

clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR) submission.zip