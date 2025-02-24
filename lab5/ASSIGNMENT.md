**Building on Project #4:**  
- In Project #3, you implemented a client-server system where the client sent file metadata in JSON format to the server.  
- Project #5 builds on this by enabling the server to handle multiple clients, each potentially registering the same or different files. Here, the server will store a list of clients (IP and port) for each unique file, rather than re-registering files that already exist in its records.  

**Detailed Requirements:**  

1. **Data Structure Design:**  
   - The server will use a linked-list-based data structure, `FileInfo`, to track file details and associated client information.  
   - The `FileInfo` structure will include:  
     ```c
     struct FileInfo {
         char filename[100];
         char fullFileHash[65]; // SHA-256 hash is 64 hex digits + null terminator
         char clientIP[MAXPEERS][INET_ADDRSTRLEN];
         int clientPort[MAXPEERS];
         int numberOfPeers;
         struct FileInfo *next; // Pointer for linked list
     };
     ```  

2. **Functionality:**  
   - **File Registration:**  
     - Upon receiving JSON data from a client, the server will extract file information, including the `filename`, `fullFileHash`, client IP, and client port.  
     - The server will check if the `fullFileHash` already exists in the linked list:  
       - **If it exists:** Append the client's IP and port to the existing entry's arrays and increment `numberOfPeers`.  
       - **If it doesn’t exist:** Create a new `FileInfo` node and link it to the list.  
   - **Handling Duplicates:** Avoid duplicate entries for the same client registering a file.  

3. **Output and Searchability:**  
   - The server can display or search for files by hash, listing each file’s clients.  
   - This enables efficient querying of which clients possess specific files, facilitating file sharing and management.  

**Learning Objectives:**  
- Extending linked-list structures for dynamic storage.  
- Building on Project #4 to support multiple clients in a peer-to-peer setup.  
- Managing unique identifiers in a networked environment to avoid redundant data storage.  