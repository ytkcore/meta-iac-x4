# =============================================================================
# Native Terraform Import Blocks - 60-db
# =============================================================================

/*
# PostgreSQL
import {
  to = module.postgres.aws_security_group.this
  id = "SG_ID"
}

import {
  to = module.postgres.module.instance.aws_instance.this
  id = "INSTANCE_ID"
}

import {
  to = aws_route53_record.postgres[0]
  id = "ZONE_ID_postgres.env.project_A"
}

# Neo4j
import {
  to = module.neo4j.aws_security_group.this
  id = "SG_ID"
}

import {
  to = module.neo4j.module.instance.aws_instance.this
  id = "INSTANCE_ID"
}

import {
  to = aws_route53_record.neo4j[0]
  id = "ZONE_ID_neo4j.env.project_A"
}
*/
