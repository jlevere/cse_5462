# **Project #7: Distributed File Retrieval and Reconstruction with Validation**

## **Overview**

In this project, students will implement a distributed file retrieval system where the clients are responsible for retrieving file chunks from other clients. The server's role is limited to maintaining and providing metadata, which includes information about available files and the IP addresses and ports of the clients holding the chunks. The requesting client will communicate directly with other clients to retrieve the file chunks, validate their integrity, and reconstruct the file. The final reconstructed file will also be validated for completeness and correctness using SHA-256 hashes.

This project builds on the concepts introduced in previous projects, particularly Project #3 (chunking and hashing), Project #4 (JSON-based communication), and Project #6 (metadata querying).

## **Learning Objectives**

By completing this project, students will:

- **Understand distributed file systems:**

  - Learn how to implement a file retrieval mechanism in a distributed environment.
  - Manage client-to-client communication for file chunk transfer.

- **Enhance data validation and integrity skills:**

  - Use SHA-256 hashes to verify the correctness of individual chunks and the complete file.

- **Practice metadata-driven operations:**

  - Implement protocols to fetch and utilize metadata for decentralized file retrieval.

- **Implement sequential and error-resilient data retrieval:**
  - Coordinate file retrieval from multiple sources and ensure error handling during the process.

## **New Concepts Introduced**

- **Client-to-Client File Retrieval:**  
  Enabling direct data transfer between clients based on metadata provided by the server.

- **Sequential Chunk Retrieval and Validation:**  
  Managing requests for file chunks in an ordered manner and validating each chunk upon receipt.

- **Complete File Reconstruction:**  
  Combining validated chunks into a complete file and verifying its correctness with the overall hash.

- **Resilient Communication Protocols:**  
  Handling errors, such as unresponsive clients or invalid data, during the retrieval process.

## **Tasks**

### **Server-Side Tasks:**

- Maintain metadata about available files, including their SHA-256 hash, chunk information, and the IP addresses and ports of clients holding the chunks.
- Respond to client queries for file metadata.

### **Client-Side Tasks (File Requester):**

- Query the server for metadata about the desired file.
- Use the metadata to determine which clients hold the required chunks.
- Retrieve each chunk sequentially by directly communicating with the relevant clients.
- Validate the integrity of each chunk using its SHA-256 hash.
- Reconstruct the file by combining validated chunks in the correct order.
- Validate the reconstructed file using its overall SHA-256 hash.

### **Client-Side Tasks (Chunk Holders):**

- Respond to requests for file chunks from other clients.
- Serve the requested chunks along with their corresponding SHA-256 hashes.

## **Key Features**

- **Metadata-Driven Retrieval:** Clients rely on server-provided metadata to locate file chunks.
- **Peer-to-Peer Communication:** File chunks are transferred directly between clients.
- **Hash-Based Validation:** Ensures the integrity of each chunk and the final file.
- **Error Handling:** Robust mechanisms for retrying requests and handling invalid or missing data.

## **Sample Workflow**

1. The client queries the server for a JSON containing metadata about the desired file, including:

   - File name, size, and SHA-256 hash.
   - List of chunks with their hashes.
   - IP addresses and ports of clients holding the chunks.

2. The client uses the metadata to:

   - Identify which client holds each chunk.
   - Sequentially request and retrieve each chunk.
   - Validate each chunk's hash upon receipt.

3. Once all chunks are retrieved and validated, the client:
   - Reconstructs the file by combining the chunks in the correct order.
   - Computes the hash of the reconstructed file and compares it to the metadata to ensure completeness and correctness.

## **Expected Outcome**

By the end of this project, students will have a distributed file retrieval system capable of retrieving, validating, and reconstructing files in a decentralized manner. This will provide hands-on experience with distributed systems, peer-to-peer communication, and data integrity validation.

## **Challenges to Anticipate**

- Coordinating communication with multiple clients to retrieve chunks in the correct order.
- Handling scenarios where clients are unresponsive or send invalid data.
- Ensuring the reconstructed file matches the original file in both content and integrity.

## **Deliverables**

- A fully functional client-server application with:
  - Metadata querying and provision by the server.
  - Peer-to-peer chunk retrieval by the client.
  - Chunk and file validation using SHA-256 hashes.
  - File reconstruction from validated chunks.
- Documentation explaining how the application works, including protocols and validation mechanisms.
- A demonstration of the system retrieving and reconstructing a sample file.

## **Tools and Libraries**

- **cJSON** for JSON manipulation.
- **OpenSSL or another hashing library** for SHA-256 calculations.
- Standard networking libraries in C (e.g., `socket.h`).
