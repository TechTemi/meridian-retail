# Meridian Retail PostgreSQL Backup and Restore Strategy

## Purpose

D9 establishes and qualifies a logical PostgreSQL backup and restore
mechanism for Meridian Retail.

The implementation builds on the frozen D8 least-privilege database
baseline and is designed to recover database state without deleting or
replacing the canonical PostgreSQL Docker volume.

## D8 database topology

The D8 database architecture separates application data into the
following service schemas:

- `auth`
- `catalog`
- `orders`

The principal application tables are:

- `auth.users`
- `catalog.products`
- `orders.orders`

The catalog schema also contains the sequence used by the products
table.

Application services use separate least-privilege PostgreSQL runtime
identities. The administrative PostgreSQL identity remains reserved for
database administration and controlled maintenance operations.

## Backup implementation

The backup entry point is:

```text
scripts/backup_db.sh
```

The script performs the following controls before reporting success:

1. enables strict Bash execution with `set -Eeuo pipefail`;
2. applies `umask 077`;
3. confirms the PostgreSQL container exists;
4. confirms the container is running;
5. validates container health when a health check exists;
6. determines the database name from the running PostgreSQL container;
7. creates a PostgreSQL custom-format logical dump;
8. verifies the resulting artifact is non-empty;
9. validates the archive with `pg_restore --list`;
10. creates a SHA-256 checksum sidecar; and
11. reports `BACKUP PASS` only after all checks succeed.

## Backup format

Backups use:

```text
pg_dump --format=custom
```

The custom archive format is used so the archive can be validated and
restored with `pg_restore`.

The dump is generated using the administrative PostgreSQL identity
already provided to the running database container.

Database credentials are not hard-coded into the backup script and are
not included in the backup filename.

## Backup location

The backup script has a standalone fallback rooted at `/opt/meridian-retail`.
That fallback is retained for script portability, but it is not the governed
production D9 location.

The actual Meridian production runtime root is `/opt/meridian`.

The D9 production systemd service explicitly supplies
`MERIDIAN_ROOT=/opt/meridian` and
`BACKUP_DIR=/opt/meridian/backups/d9`.

Therefore production automation does not depend on the standalone fallback.
`/opt/meridian/backups/d9` is the exact directory used during D9 production
backup and restore qualification.

The backup script creates the selected backup directory when required and
restricts its permissions.
## Backup naming

Backup artifacts use a UTC timestamp and follow this pattern:

```text
meridian-<database>-<YYYYMMDDTHHMMSSZ>.dump
```

Each archive has a checksum sidecar:

```text
meridian-<database>-<YYYYMMDDTHHMMSSZ>.dump.sha256
```

A backup is not accepted as successful unless both the archive and
checksum are present and the archive passes structural validation.

## Restore implementation

The restore entry point is:

```text
scripts/restore_db.sh
```

Its normal D9 target is:

```text
meridian_d9_restore
```

The restore implementation is intentionally isolated from the live
source database.

## Restore safety controls

The restore script unconditionally refuses to restore directly over the live
source database.

It also unconditionally refuses target database names that do not begin with:

```text
meridian_d9_
```

These protections have no operator bypass in the D9 restore implementation.

## Restore validation sequence

Before restoration, the script:

1. confirms the backup file exists;
2. confirms the backup is non-empty;
3. requires the corresponding SHA-256 checksum sidecar;
4. validates the checksum;
5. validates the archive using `pg_restore --list`;
6. confirms the PostgreSQL container exists and is running;
7. confirms container health when available;
8. determines the live source database;
9. applies target-database safety checks; and
10. recreates the isolated D9 restore database.

The archive is then restored using `pg_restore --exit-on-error`.

If restoration fails, the incomplete D9 restore database is removed and
the operation fails closed.

## Post-restore D8 structural validation

A successful restore must preserve the D8 schema topology.

The restore script requires the following relations:

```text
auth.users
catalog.products
orders.orders
```

It also requires the old pre-D8 public-schema application tables to be
absent:

```text
public.users
public.products
public.orders
```

The restore script reports:

```text
RESTORE PASS
```

only after this structural validation succeeds.

## Role and ownership considerations

`pg_dump` captures database objects, ownership metadata, and access
control metadata.

PostgreSQL roles themselves are cluster-level objects and are not
created by an ordinary logical database dump.

D9 therefore assumes the D8 PostgreSQL administrative and service roles
already exist in the target PostgreSQL cluster.

No PostgreSQL role password is exported into the D9 backup artifact.

## Canonical PostgreSQL volume

The production PostgreSQL data volume is:

```text
meridian-postgres-data
```

D9 does not require removal or replacement of this volume.

Normal D9 restore testing occurs in a separate PostgreSQL database
inside the existing database cluster.

This allows recovery behavior to be proven without destructive
replacement of the canonical production volume.

## D9 runtime qualification

The implementation alone does not complete D9.

Runtime qualification must still prove that:

1. a controlled application record exists before backup;
2. a valid backup is created;
3. the controlled record exists in the restored verification database;
4. the controlled record can be deleted from the verification database;
5. the deletion is observable;
6. restoring the same backup causes the record to reappear;
7. source and restored database state are consistent;
8. D8 schema ownership and privilege expectations remain valid;
9. application services remain healthy;
10. the canonical PostgreSQL volume remains present and unchanged; and
11. the process can be repeated deterministically.

These checks belong to the D9 qualification gate rather than being
assumed from script execution alone.

## Production recovery boundary

Normal D9 qualification does not perform an in-place restore of the live
production database.

A real in-place production recovery would require additional operational
controls, including:

- a maintenance window;
- application quiescence;
- an immediate pre-restore backup;
- rollback criteria;
- explicit operator approval;
- post-restore application validation; and
- documented recovery evidence.

The live-database protection in `restore_db.sh` is therefore intentional.

## Scheduling and retention

D9 implements explicit source-controlled daily PostgreSQL backup automation
using systemd.

The source-controlled scheduling artifacts are
`ops/systemd/meridian-db-backup.service`,
`ops/systemd/meridian-db-backup.timer`, and
`ops/systemd/install-d9-backup-systemd.sh`.

The timer uses `OnCalendar=daily` and `Persistent=true`.

The service executes `/opt/meridian/app/scripts/backup_db.sh` and explicitly
sets `MERIDIAN_ROOT=/opt/meridian` and
`BACKUP_DIR=/opt/meridian/backups/d9`.

The installer copies the already-qualified backup implementation into its
production location, installs the systemd units, reloads systemd, and enables
the timer. It deliberately does not start the timer and does not execute a
backup. Activation and first scheduled-service execution are qualified as
separate production runtime steps.

D9 does not introduce automatic retention/deletion, remote object-storage
replication, or encryption-key lifecycle. Those remain later operational
hardening controls.
