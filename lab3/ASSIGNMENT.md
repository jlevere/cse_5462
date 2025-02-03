# Project #3: File Chunking and Hashing for Integrity Verification

In this project, you will expand on the existing code from Lab 2. Your objective is to further segment files into chunks, generate SHA-256 hashes for each chunk, and create a whole-file hash for each file in the specified directory. This integrity information will be organized into JSON objects for each file. All existing functions from Lab 2 should still function correctly as part of this expanded functionality.

---

## Learning Objectives

1. **Understand File Segmentation and Hashing**:
   - Learn to divide a file into consistent-sized chunks and generate unique identifiers (hashes) for each chunk.
   - Gain experience in hashing both segments and entire files for verification.

2. **Mastery of SHA-256 for Data Integrity**:
   - Apply SHA-256 hashing to both chunks and whole files, reinforcing the use of cryptographic hashing functions to maintain data integrity.
   - Understand the importance of data integrity checks, particularly in file transfer and storage applications.

3. **JSON Object Creation for Metadata**:
   - Learn to encapsulate file metadata, including filename, size, number of chunks, and hash values, within a structured JSON format.
   - Understand how JSON formatting can be used to convey complex data structures in a human-readable and programmatically accessible way.

4. **Apply Sequential Logic in File Processing**:
   - Develop skills in performing a series of operations on each file in a directory, particularly ensuring that all hash generation occurs before file transfer.
   - Reinforce the concept of sequential processing to ensure consistent data handling and reduce errors in complex tasks.

---

## Project Requirements

1. **Chunking Files**:
   - Given a directory, create a subdirectory called `CHUNKS`.
   - Divide each file within the directory into chunks of exactly `500 * 1024` bytes (500 KB).
   - Name each chunk using its SHA-256 hash value to ensure unique identification.

2. **Hashing**:
   - For each chunk, compute a SHA-256 hash and store it as the chunk’s filename in the `CHUNKS` directory.
   - Additionally, compute a SHA-256 hash for the entire file (whole-file hash), which will not alter the original filename.
   - Perform these hashing operations **before** transferring any data or messages from the file.

3. **JSON Metadata**:
   - For each file, create a JSON object in the following format:

     ```json
     {
       "filename": "ExampleFile.jpeg",
       "fileSize": 1234567,
       "numberOfChunks": 6,
       "chunk_hashes": [
         "hash_chunk_1",
         "hash_chunk_2",
         ...
       ],
       "fullFileHash": "hash_for_whole_file"
     }
     ```

   - Each JSON object should contain:
     - `"filename"`: Original filename of the file.
     - `"fileSize"`: Total size of the file in bytes.
     - `"numberOfChunks"`: Number of chunks the file was split into.
     - `"chunk_hashes"`: Array of SHA-256 hashes for each chunk.
     - `"fullFileHash"`: SHA-256 hash for the entire file.

---

This JSON metadata will allow for validation of both individual file chunks and the full file. Ensure that all steps execute as expected, as existing functions from Lab 2 will be essential for verifying and transferring file data correctly.