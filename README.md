# OSU Undergraduate Class SP '25 - CSE 5462

## Network Programming

This is an elective - focused on network programming

Learn by doing. From "Hello World" over UDP to multi-peer file registries, this class transforms theoretical socket networking concepts into tangible, scalable systems on real networks.

*Course Level:* Undergraduate/Graduate

*Units:* 3

*Instructors:* Dr. David Ogle <David.ogle@ucdenver.edu> <ogle.87@osu.edu>

*Instruction Mode:* Online

*Lectures:* Tue and Thu, 15:55 – 17:15 Zoom

*Office Hours:* Wed 17:30-18:30 [UC Den Zoom Office Hours](https://ucdenver.zoom.us/my/daveogle)

## Class Summary

This course focuses on building **scalable networked systems** through hands-on projects that progress from foundational networking concepts to advanced distributed file-sharing architectures. Students learn to design and implement systems that handle real-world challenges like data integrity, efficient communication, and multi-client coordination.

## Project Progression


1. **Foundations**
   UDP-based multicast communication, socket programming, key-value parsing, and formatting dynamic output

2. **Structured Data**
   Transition to JSON object transmission, serialization/deserialization for structured file metadata

3. **Data Integrity**
   File chunking and SHA-256 hashing, cryptographic verification of file integrity

4. **Scalability**
   Dynamic server-client ecosystem where servers track file ownership across peers using linked lists, enabling efficient queries and redundancy-free storage


## Repo Info

This repo is a personal monorepo for the class, but the class is actually comprised of a repo for each assignemnt under a github classroom org for the semester.

To help this clean, I am using subtree with each of the assignment repos grafted into my monorepo.  This alows for me to work in the monorepo but then push things to their correct repo for the class.

The commands for this:

`git remote add lab0 git@github.com:CSE-5462-OSU-Spring2025/lab0-jLevere.git`

`git subtree add --prefix=lab0 lab0 main --squash`

`git subtree push --prefix=lab0 lab0 main`

Where `lab0` is the name of the remote repo and `lab0/` is the monorepo location for it.  This works quite nicely.

# Repository Structure & Workflow


## Why This Structure?

This setup balances developer convenience (a clean monorepo with automated environment setup) with external class requirements (compiled binaries, strict compatibility, and grading policies).


## Monorepo Strategy with Git Subtrees
This repository consolidates all class assignments (hosted as separate GitHub Classroom repos) using **Git subtrees** for central management.

### Key Commands:  
```bash
# Add an assignment repo as a remote
git remote add lab0 git@github.com:CSE-5462-OSU-Spring2025/lab0-jLevere.git

# Pull the assignment into a subdirectory of the monorepo
git subtree add --prefix=lab0 lab0 main --squash

# Push changes back to the dedicated assignment repo
git subtree push --prefix=lab0 lab0 main
```

Each lab (e.g., lab0/) lives in its own subdirectory, synced with its classroom repository.

## Development Environment (Nx/Zig)

Nix flakes ensure reproducible development environments. This is critical for:

- Maintaining a consistent `zig` version throughout the course.
- Synchronizing `zig` and `zls` (Zig Language Server) versions, which can be complex.

### Why Zig’s Pre-Release Status Matters:

Zig is under active development, with frequent breaking changes. Using a specific commit (rather than tagged releases) ensures stability while leveraging new features.

## CI/CD Pipeline

Automated workflows handle:

1. Builds & Tests:
    - Compilation checks
    - Unit testing

2. Compatibility Testing:
    - Validates binaries in standardized academic environments (e.g., stdlinux-compat Docker images).

3. Scheduled Releases:
    - Automates versioned releases (e.g., 2024.03.04.2) tied to assignment deadlines.