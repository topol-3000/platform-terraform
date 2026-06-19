# Module: efs
# Purpose: Shared EFS filesystem (per-tenant access points created by the adapter)
#
# SEED-001 note: Mounted at /var/lib/odoo, durable across task replacement / cross-AZ reschedule (NOT EBS). Watch small-file latency under /sessions.
#
# STATUS: stub. No resources yet.
# See ../../../provisioner/.planning/seeds/SEED-001-aws-real-deployment.md
#
# TODO: implement Shared EFS filesystem (per-tenant access points created by the adapter)
