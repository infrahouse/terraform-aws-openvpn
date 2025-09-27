import logging

from infrahouse_core.logging import setup_logging


LOG = logging.getLogger(__name__)
TERRAFORM_ROOT_DIR = "test_data"


setup_logging(LOG, debug=True)
