import logging

from infrahouse_core.logging import setup_logging


LOG = logging.getLogger(__name__)
TERRAFORM_ROOT_DIR = "test_data"


# Configure root logger so all loggers (including pytest_infrahouse, infrahouse_core, etc.) inherit the config
setup_logging(logging.getLogger(), debug=False, debug_botocore=False)
