.PHONY: clean help all

CC = zig

SRC_DIR = src

SRC = $(wildcard $(SRC_DIR)/*.zig)

TARGET = client server

all: $(TARGET)

$(TARGET):
	$(CC) build-exe $(SRC_DIR)/$@.zig -O ReleaseSafe -fstrip

help:
	@echo "Available targets:"
	@echo "  help        - Show this help message"
	@echo "  clean       - Remove build artifacts"
	@echo "  submission  - Create zip to submit"
	@echo "  all         - Build the program (default target)"

submission:
	zip -r submission.zip $(SRC_DIR) Makefile README.md ASSIGNMENT.md

clean:
	rm -rf submission.zip server client *.o zig-out .zig-cache
