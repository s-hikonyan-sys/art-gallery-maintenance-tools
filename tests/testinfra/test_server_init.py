def test_sshd_service(host):
    service = host.service("sshd")
    assert service.is_enabled
    assert service.is_running


def test_docker_service(host):
    service = host.service("docker")
    assert service.is_enabled
    assert service.is_running


def test_ssh_admin_user_exists(host):
    user = host.user("ssh-admin")
    assert user.exists
    assert user.home == "/home/ssh-admin"


def test_sshd_config_has_allowusers(host):
    config = host.file("/etc/ssh/sshd_config")
    assert config.exists
    assert config.contains(r"^AllowUsers\s+ssh-admin$")


def test_firewalld_services(host):
    cmd = host.run("firewall-cmd --list-services --zone=public")
    assert cmd.rc == 0
    services = cmd.stdout.split()
    assert "ssh" in services
    assert "http" in services
    assert "https" in services


def test_certbot_renew_timer(host):
    timer = host.service("snap.certbot.renew.timer")
    assert timer.is_enabled
    assert timer.is_running


def test_certificate_domain(host, target):
    domain = target.get("domain")
    if not domain:
        return
    certs = host.run("certbot certificates")
    assert certs.rc == 0
    assert domain in certs.stdout
