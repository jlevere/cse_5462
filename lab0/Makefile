.PHONY: clean help all

CC = gcc
CFLAGS = -g -I. -Wall -Werror


SRC_DIR = src
OBJ_DIR = obj
BIN_DIR = bin

TARGET = $(BIN_DIR)/client $(BIN_DIR)/server

all: $(TARGET)

client: $(BIN_DIR)/client
server: $(BIN_DIR)/server

$(BIN_DIR) $(OBJ_DIR):
	@mkdir -p $@

$(BIN_DIR)/client: $(OBJ_DIR)/client.o | $(BIN_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(BIN_DIR)/server: $(OBJ_DIR)/server.o | $(BIN_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@


run: all
	@$(TARGET) || true

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