import os
import pytest
import testinfra


def pytest_addoption(parser):
    parser.addoption(
        "--target-host",
        action="store",
        default=os.getenv("TARGET_HOST"),
        help="SSH target host/IP",
    )
    parser.addoption(
        "--target-user",
        action="store",
        default=os.getenv("TARGET_USER", "ssh-admin"),
        help="SSH login user",
    )
    parser.addoption(
        "--target-key",
        action="store",
        default=os.getenv("TARGET_KEY"),
        help="SSH private key path",
    )
    parser.addoption(
        "--target-domain",
        action="store",
        default=os.getenv("TARGET_DOMAIN"),
        help="Expected domain for certificate check",
    )
    parser.addoption(
        "--ssh-port",
        action="store",
        default=os.getenv("TARGET_SSH_PORT", "22"),
        help="SSH port",
    )


@pytest.fixture(scope="session")
def target(pytestconfig):
    host = pytestconfig.getoption("--target-host")
    user = pytestconfig.getoption("--target-user")
    key = pytestconfig.getoption("--target-key")
    domain = pytestconfig.getoption("--target-domain")
    port = pytestconfig.getoption("--ssh-port")

    if not host:
        pytest.skip("TARGET_HOST or --target-host is required")
    if not key:
        pytest.skip("TARGET_KEY or --target-key is required")

    return {
        "host": host,
        "user": user,
        "key": key,
        "domain": domain,
        "port": port,
    }


@pytest.fixture(scope="session")
def host(target):
    conn = (
        f"ssh://{target['user']}@{target['host']}"
        f"?port={target['port']}&identity_file={target['key']}"
    )
    return testinfra.get_host(conn)
