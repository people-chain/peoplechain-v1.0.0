PeopleChain Monitor • Database-style CRUD examples

This folder demonstrates simple CRUD operations against the monitor server's demo document API.

Important
- This is a demo, in-memory document store exposed by the monitor at /api/db/*.
- Data is NOT persisted to disk and will be cleared when the node restarts.
- Endpoints are CORS-enabled so you can call them from browsers or scripts.

Base URL
- Default: http://127.0.0.1:8081
- If you changed PEOPLECHAIN_MONITOR_PORT or host, adjust the URL in the samples.

Endpoints
- POST   /api/db/{collection}              -> create a document (auto id if none provided)
- GET    /api/db/{collection}              -> list documents (limit, offset, q)
- GET    /api/db/{collection}/{id}         -> read a document
- PUT    /api/db/{collection}/{id}         -> replace/create document
- PATCH  /api/db/{collection}/{id}         -> shallow merge update
- DELETE /api/db/{collection}/{id}         -> delete document

Query params (list)
- limit: integer (default 50)
- offset: integer (default 0)
- q: case-insensitive substring filter applied to JSON string of data

Samples
- python_crud_example.py  — Python 3 + requests
- node_crud_example.js    — Node.js 18+ (global fetch)
- java_crud_example.java  — Java 11+ (HttpClient)
- curl_crud.sh            — cURL cheat sheet

Run order suggestion
1) Create a few items (POST)
2) List and filter them (GET with q)
3) Read a single item (GET by id)
4) Update or patch it (PUT/PATCH)
5) Delete it (DELETE)
