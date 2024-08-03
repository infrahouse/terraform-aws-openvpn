import json
from io import BytesIO
from logging import getLogger
from os import environ
from os import path as osp
from subprocess import check_call
from textwrap import dedent


import boto3
import requests
from asgiref.wsgi import WsgiToAsgi
from flask import (
    Flask,
    redirect,
    url_for,
    session,
    abort,
    request,
    send_file,
    send_from_directory,
)
from flask_dance.contrib.google import make_google_blueprint, google
from infrahouse_toolkit.cli.ih_secrets.cmd_get import get_secret
from infrahouse_toolkit.logging import setup_logging
from oauthlib.oauth2 import TokenExpiredError
from werkzeug.middleware.proxy_fix import ProxyFix

LOG = getLogger()
DEBUG = bool(environ.get("DEBUG"))
EASY_RSA = "/usr/share/easy-rsa/easyrsa"
setup_logging(LOG, debug=DEBUG)


aws_client = boto3.client("secretsmanager")

app = Flask(__name__, static_folder="assets")
app.wsgi_app = ProxyFix(app.wsgi_app)
app.secret_key = get_secret(aws_client, environ["FLASK_SECRET_KEY"])
google_oauth_client_secret_value = json.loads(
    get_secret(aws_client, environ["GOOGLE_OAUTH_CLIENT_SECRET_NAME"])
)
openvpn_config_directory = environ.get("OPENVPN_CONFIG_DIRECTORY", "/etc/openvpn")

# Replace with your Google OAuth2 credentials
google_bp = make_google_blueprint(
    client_id=google_oauth_client_secret_value["web"]["client_id"],
    client_secret=google_oauth_client_secret_value["web"]["client_secret"],
    scope=[
        "openid",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/userinfo.email",
    ],
)

app.register_blueprint(google_bp, url_prefix="/login")
asgi_app = WsgiToAsgi(app)


@app.route("/")
def index():
    LOG.debug("google.authorized = %s", google.authorized)
    if not google.authorized:
        return redirect(url_for("google.login"))

    try:
        resp = google.get("/oauth2/v2/userinfo")
        assert resp.ok, resp.text
        LOG.debug("get('/oauth2/v2/userinfo') = %s", resp.text)
        email = resp.json()["email"]
        name = resp.json()["name"]

        # Generate a certificate if it doesn't exist
        ensure_certificate(openvpn_config_directory, email)

        return index_page(name, email)
    except TokenExpiredError:
        return redirect(url_for("google.login"))


@app.route("/profile")
def profile():
    LOG.debug("google.authorized = %s", google.authorized)
    if not google.authorized:
        return redirect(url_for("google.login"))

    openvpn_hostname = environ["OPENVPN_HOSTNAME"]
    resp = google.get("/oauth2/v2/userinfo")
    assert resp.ok, resp.text
    LOG.debug("get('/oauth2/v2/userinfo') = %s", resp.text)
    email = resp.json()["email"]

    file_obj = BytesIO()
    file_obj.write(
        generate_profile(
            openvpn_config_directory,
            email,
            openvpn_hostname,
            environ["OPENVPN_PORT"],
        ).encode()
    )
    file_obj.seek(0)  # Reset file pointer to beginning

    return send_file(
        file_obj,
        mimetype="application/x-openvpn-profile",
        as_attachment=True,
        download_name=f"{email}-{openvpn_hostname}.ovpn",
    )


@app.route("/login/google")
def google_login():
    redirect_url = redirect(url_for("google.login"))
    LOG.debug("redirect_url = %s", redirect_url)
    return redirect_url


@app.route("/logout")
def logout():
    if google.authorized:
        userinfo = google.get("/oauth2/v2/userinfo")
        token = google.token["access_token"]
        # Revoke the token on Google's side
        resp = requests.post(
            "https://accounts.google.com/o/oauth2/revoke",
            params={"token": token},
            headers={"content-type": "application/x-www-form-urlencoded"},
        )
        if resp.status_code == 200:
            # Clear the user session
            del google.token
            session.clear()
            LOG.info(f"Successful logout for %s", json.dumps(userinfo.json(), indent=4))
            return redirect(url_for("index"))
        else:
            return "Failed to revoke token", 400
    return redirect(url_for("index"))


@app.route("/status")
def status():
    if not osp.exists(openvpn_config_directory):
        LOG.error(
            "OpenVPN configuration directory %s doesn't exist.",
            openvpn_config_directory,
        )
        abort(500)

    return "OK"


@app.route("/favicon.ico")
def favicon():
    return send_from_directory(
        app.static_folder, "favicon.ico", mimetype="image/vnd.microsoft.icon"
    )


def generate_client_key(config_dir, email):
    # Generate request
    check_call(
        [EASY_RSA, f"--vars={config_dir}/vars", "gen-req", email, "nopass"],
        cwd=config_dir,
        env={"EASYRSA_REQ_CN": email},
    )
    # Sign the client request
    check_call(
        [EASY_RSA, f"--vars={config_dir}/vars", "sign-req", "client", email],
        env={"EASYRSA_PASSIN": f"file:{openvpn_config_directory}/ca_passphrase"},
        cwd=config_dir,
    )


def ensure_certificate(config_dir, email):
    cert_path = osp.join(config_dir, "pki", "issued", f"{email}.crt")
    if not osp.exists(cert_path):
        generate_client_key(config_dir, email)


def generate_profile(config_dir, email, vpn_hostname, vpn_port):
    return f"""
client
dev tun
proto tcp
remote {vpn_hostname} {vpn_port}
nobind

# Certificate Authorities, Client Certificate, and Client Key
<ca>
{open(osp.join(config_dir, "pki/ca.crt"), encoding="UTF-8").read()}
</ca>

<cert>
{open(osp.join(config_dir, f"pki/issued/{email}.crt"), encoding="UTF-8").read()}
</cert>

<key>
{open(osp.join(config_dir, f"pki/private/{email}.key"), encoding="UTF-8").read()}
</key>

<tls-auth>
{open(osp.join(config_dir, f"ta.key"), encoding="UTF-8").read()}
</tls-auth>
key-direction 1

cipher AES-256-CBC
auth SHA256

# Verbosity level
verb 3
"""


def index_page(name, email):
    domain = email.split("@")[1]
    return dedent(
        f"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>OpenVPN Portal: {domain}</title>
            <link rel="icon" href="/favicon.ico?v=3" />
            <style>
                th, td {{
                    border-style: groove;
                }}
            </style>
        </head>
        <body>
            <h1>Welcome to {domain} OpenVPN Portal</h1>
            <p>
                Logged as {name}&lt;{email}&gt;. <a href="/logout">Logout</a>
            </p>
            <h2>VPN client setup instructions</h2>
            <p><b>Step 1</b>: Download the client app</p>
            <table>
                <tr>
                    <th>MacOS</th><th>Windows</th><th>Other</th>
                </tr>
                <tr>
                    <td>
                        <p><a href="https://openvpn.net/downloads/openvpn-connect-v3-macos.dmg">MacOS Installer</a></p>
                        <p>
                            <a href="https://openvpn.net/client-connect-vpn-for-mac-os/">
                            Installation instructions and alternative versions
                            </a>
                        </p>
                    </td>
                    <td>
                        <p>
                            <a href="https://openvpn.net/downloads/openvpn-connect-v3-windows.msi">
                            Windows Installer
                            </a>
                        </p>
                        <p>
                            <a href="https://openvpn.net/client-connect-vpn-for-windows/">
                            Installation instructions and alternative versions
                            </a>
                        </p>
                    </td>

                    </td>
                    <td><a href="https://openvpn.net/client/">Other OS-es</a></td>
                </tr>
            </table>
            <p>
            <b>Step 2</b>: Download your <a href="/profile">OpenVPN profile</a>.
            </p>
            <p>
            <b>Step 3</b>: Find the profile in the file manager and open it. Follow the onscreen instructions.
        </body>
        </html>
        """
    )
