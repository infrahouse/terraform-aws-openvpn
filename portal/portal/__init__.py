import json
from logging import getLogger
from os import environ
from textwrap import dedent


import boto3
import requests
from asgiref.wsgi import WsgiToAsgi
from flask import Flask, redirect, url_for, session
from flask_dance.consumer import oauth_authorized, OAuth2Session
from flask_dance.contrib.google import make_google_blueprint, google
from infrahouse_toolkit.cli.ih_secrets.cmd_get import get_secret
from infrahouse_toolkit.logging import setup_logging
from werkzeug.middleware.proxy_fix import ProxyFix

LOG = getLogger()
DEBUG = bool(environ.get("DEBUG"))
setup_logging(LOG, debug=DEBUG)


aws_client = boto3.client("secretsmanager")

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app)

app.secret_key = get_secret(aws_client, environ["FLASK_SECRET_KEY"])
# environ['OAUTHLIB_INSECURE_TRANSPORT'] = '1'

google_oauth_client_secret_value = json.loads(
    get_secret(aws_client, environ["GOOGLE_OAUTH_CLIENT_SECRET_NAME"])
)

# Replace with your Google OAuth2 credentials
google_bp = make_google_blueprint(
    client_id=google_oauth_client_secret_value["web"]["client_id"],
    client_secret=google_oauth_client_secret_value["web"]["client_secret"],
    scope=[
        "openid",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/userinfo.email",
    ],
    # redirect_url="https://openvpn-portal.ci-cd.infrahouse.com/login/google/authorized",
    # redirect_to="google_login",
)

app.register_blueprint(google_bp, url_prefix="/login")


asgi_app = WsgiToAsgi(app)


# @oauth_authorized.connect_via(google_bp)
# def google_logged_in(blueprint, token):
#     oauth = OAuth2Session(
#         blueprint.client_id,
#         redirect_uri='https://openvpn-portal.ci-cd.infrahouse.com/login/google/authorized'
#     )
#     blueprint.session = oauth


@app.route("/")
def index():
    LOG.debug("google.authorized = %s", google.authorized)
    if not google.authorized:
        return redirect(url_for("google.login"))
    resp = google.get("/oauth2/v2/userinfo")
    assert resp.ok, resp.text
    LOG.debug("get('/oauth2/v2/userinfo') = %s", resp.text)
    return dedent(
        f"""
        <p>
            You are <pre>{json.dumps(resp.json(), indent=4)}</pre> on Google.
        </p>
        <p>
            <a href="/logout">Logout</a>
        </p>
        """
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
    return "OK"
