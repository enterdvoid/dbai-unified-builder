# Backup and Release Recovery

The builder publishes only after all matrix jobs have completed successfully. Each image asset is renamed with board, release, profile, and filesystem identifiers and receives a JSON manifest and SHA-256 checksum.

If release creation or remote checksum verification fails, the workflow attempts to delete the partially created release and tag. It does not delete previous successful releases on a failed run. Older `dbai-build-*` releases are removed only after the new release has been downloaded and verified and only when the cleanup input is enabled.

The source repository backup workflow remains in `enterdvoid/build`. It requires the `DBAI_RELEASE_TOKEN` secret because the initial test with the default Actions token received HTTP 403 when creating a release. See the [backup workflow](https://github.com/enterdvoid/build/blob/main/.github/workflows/dbai-backup.yml) and [backup instructions](https://github.com/enterdvoid/build/blob/main/docs/DBAI-BACKUP-RESTORE.md).

For a fine-grained token, grant access only to `enterdvoid/build` and `enterdvoid/dbai-unified-builder`, with repository Contents read/write and Metadata read. Store the token separately as an Actions secret in each repository. Never commit it.
