# LUB Protocol draft

## Legacy bridge-manifest.json (formatVersion 1)

```json
{
  "formatVersion": 1,
  "project": "SampleProject",
  "version": "1.0.1",
  "description": "Example safe update",
  "files": [
    {
      "source": "payload/README.txt",
      "destination": "README.txt",
      "sha256": "<64 lowercase SHA-256 hex characters>"
    }
  ]
}
```

Payload files must be stored under `payload/`. This schema is compatible with the existing SwiftUI app's v1 manifest. The planned v2 protocol will add explicit operations (add/replace/delete), expected hashes, dependencies, build/test descriptors, changelog, and versioned machine-readable diagnostics. It must be designed without breaking v1 readers.
