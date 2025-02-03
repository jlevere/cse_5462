# Project 2: JSON Object Transmission

## Intro

This project implements UDP-based transmission of serialized JSON objects between a client and server using multicast. 

Building on Project \#1's key-value implementation, this version transitions to structured JSON objects containing file metadata. The server joins a multicast group, receives serialized JSON data, deserializes it, and prints the parsed results in a human-readable format.


## Contents
- Assignment [details](ASSIGNMENT.md)
- [Getting Started](#getting-started)
- [Design](#design)
- [Key Concepts](#key-concepts)
- [Testing](#testing) [![Main code fmt and test](https://github.com/CSE-5462-OSU-Spring2025/lab2-jLevere/actions/workflows/main.yaml/badge.svg)](https://github.com/CSE-5462-OSU-Spring2025/lab2-jLevere/actions/workflows/main.yaml)


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

Compile with `zig build` or download pre-built binaries from [releases](https://github.com/CSE-5462-OSU-Spring2025/lab2-jLevere/releases/latest/).

### Usage


```
./server 224.0.0.1 8011
```

```
./client 224.0.0.1 8011 input.txt
```


### In action

![pt1](./docs/lab2-pt1.png)

![pt2](./docs/lab2-pt2.png)




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

