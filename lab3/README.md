# Project #3: File Chunking and Hashing for Integrity Verification

## Intro

This project focuses on verifying file integrity by splitting files into 500KB chunks, generating SHA-256 hashes for each chunk and the entire file, and organizing this data into structured JSON metadata. 

It builds on existing code to ensure files are hashed, chunked, and validated before transfer, maintaining data integrity for storage or transmission. 

The JSON output provides a human-readable record of filenames, sizes, chunk counts, and cryptographic hashes for both individual segments and complete files.


## Contents
- Assignment [details](ASSIGNMENT.md)
- [Getting Started](#getting-started)
- [Design](#design)
- [Key Concepts](#key-concepts)
- [Testing](#testing) [![Main code fmt and test](https://github.com/CSE-5462-OSU-Spring2025/lab3-jLevere/actions/workflows/main.yaml/badge.svg)](https://github.com/CSE-5462-OSU-Spring2025/lab3-jLevere/actions/workflows/main.yaml)


## Getting Started


To compile the code you have a few options, use the [development enviroment](#enviroment-setup), or [directly install](#direct-zig-install) the zig compiler.

### Enviroment setup (HIGHLY RECOMENDED)

To use the Nix flake-based development environment:
```bash
direnv allow  # or
nix develop
```

This will ensure that the LSP, compiler and library versions are all in sync using the `flake.lock` file.

To learn more about how awesome nix is, see [how-nix-works](https://nixos.org/guides/how-nix-works/) and the [nix-installer](https://github.com/DeterminateSystems/nix-installer).

### Direct Zig Install

For MacOS (via Homebrew):
```bash
brew install zig  # v0.13.0 (0.14.0-dev.2851+b074fb7dd recommended)
```
Other systems: [Download binaries](https://ziglang.org/learn/getting-started/) or check [supported package managers](https://github.com/ziglang/zig/wiki/Install-Zig-from-a-Package-Manager).

### Compilation & Usage

Compile with `zig build` or download pre-built binaries from [releases](https://github.com/CSE-5462-OSU-Spring2025/lab3-jLevere/releases/latest/).

### Usage


```
./server 224.0.0.1 8011
```

```
./client 224.0.0.1 8011 input.txt
```

## Design

### JSON Object Structure
Client creates JSON objects containing:
- `File_Name`: String (e.g., "Presentation4.otp")
- `File_Size`: String (e.g., "4MB")
- `File_Type`: String (e.g., "Presentation")
- `Date_Created`: Date string (e.g., "2024-07-05")
- `Description`: String (e.g., "Webinar slide deck")


### Workflow
```mermaid
sequenceDiagram
    Client->>Client: 1. Serialize JSON
    Client->>Server: 2. Send via UDP (sendto())
    Server->>Server: 3. Deserialize JSON
    Server->>Output: 4. Print formatted data
```

## Testing
**Unit Tests:**
```bash
zig build test
```

