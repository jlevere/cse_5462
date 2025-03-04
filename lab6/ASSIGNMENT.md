# Project #6: Distributed File Information Retrieval System

**Overview**

In this project, students will develop a system where a client can retrieve and display file metadata from multiple servers over a network, without downloading the files. This builds on previous projects and introduces structured client-server communication using multicast networking and JSON serialization. The system will focus on querying and displaying file data, preparing students for file downloading in the next project.

This project will strengthen students' understanding of network programming, distributed systems, and structured data exchange.

---

## Project Objectives

1. **Implement Multicast Communication**: Learn to use multicast to broadcast a query to multiple servers at once.
2. **Structured Messaging with `requestType`**: Use the `requestType` field in JSON to differentiate between `query` requests from the client and `queryResponse` messages from the servers.
3. **Client-Server Architecture**: Develop a distributed client-server architecture that collects and displays metadata on files available across servers.
4. **JSON Data Processing**: Practice using JSON for serializing and deserializing file information.

---

## Project Requirements

### New `requestType` Field
Students will use the `requestType` field in JSON messages to distinguish message types:
- **`query`**: Sent by the client to request file information from servers.
- **`upload`**: Send by the client to upload local file information to the server.
- **`queryResponse`**: Sent by servers to respond with a list of available files and metadata.

---

### Client Implementation
The client should:

1. **Send a Multicast `query` Request**:
   - Upon user request, the client sends a multicast `query` request to discover all files across servers.
2. **Display Options in a Loop**:
   - Present a looped menu with options to either view file information or exit.
   - For file listings, display each file with a choice number, filename, size, and hash, formatted in a readable table.
3. **Format and Print JSON Data**:
   - As the client receives `queryResponse` messages, it extracts and aggregates the JSON data, displaying each file with a sequential choice number.

---

### Server Implementation
Each server should:

1. **Listen for and Respond to `query` Requests**:
   - When a server receives a `query` request, it replies with a `queryResponse` message containing a list of files it hosts.
2. **Prepare JSON Response**:
   - The server's `queryResponse` message should list each file's `filename`, `fileSize`, and `fullFileHash` in JSON format.

---

## Technical Specifications

- **Multicast Networking**:
  - Configure multicast IP and port settings as provided in the project instructions to enable simultaneous communication with all servers.

- **JSON Data with `requestType`**:
  - Use `cJSON` for parsing and formatting JSON messages. Each `queryResponse` JSON should have the structure:

```json
{
  "requestType": "queryResponse",
  "files": [
    {
      "filename": "example.txt",
      "fileSize": 1024,
      "fullFileHash": "abc123..."
    },
    ...
  ]
}
```
- **Client Display Format**: Number each file sequentially in the output to facilitate easy selection.

---

## Learning Objectives

By completing this project, students will:

+ Master Multicast Communication: Learn how to send multicast requests and handle responses from multiple servers.

+ Build Distributed Systems Skills: Develop the ability to gather and aggregate data from distributed sources across a network.

+ Apply Structured Data Handling with JSON: Use JSON to organize and present structured file metadata, reinforcing data serialization and deserialization skills.

+ Create User-Friendly Output: Learn to format and display network data in a clear, user-oriented manner.


---

## Sample Output

Below is an example of how the client might present file information based on responses from multiple servers:

**Client Console Output**

```
Select an option:
1. View Available Files
2. Exit
> 1

Files Available Across Servers:
------------------------------------------------------------
Choice | File Name       | Size    | Full Hash
------------------------------------------------------------
1      | example.txt     | 1024 B  | abc123def4567890
2      | document.pdf    | 2048 B  | fgh456ijk7890123
...
```