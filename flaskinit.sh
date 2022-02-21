#!/bin/bash
read -p "Enter project path: " path
mkdir -p $path
cd $path
python3 -m venv venv
source venv/bin/activate
pip install wheel || exit 1
pip install flask flask_cors flask_sslify mypy psycopg2 requests PyJWT python-dotenv coverage genbadge defusedxml gunicorn || exit 1
pip freeze > requirements.txt

modules_path = ""
# construct python project modules path
if [[ "${str: -1}" != '/' ]]
then
        modules_path = "$path"+"/modules"
else
        modules_path = "$path"+"modules"
fi

cat <<EOF >__init__.py
from flask import Flask, request,jsonify, make_response
from flask_cors import CORS
from flask_sslify import SSLify
import json, os, requests, sys
import jwt
from functools import wraps
from datetime import datetime, timedelta
import logging
from dotenv import load_dotenv
sys.path.append("")  # change that if you upload this to remote )(path will differ most likely)
from modules.db import DB

load_dotenv()

logging.basicConfig(level=logging.INFO, format='%(asctime)s,%(msecs)d %(levelname)-8s [%(filename)s:%(lineno)d] %(message)s', datefmt='%Y-%m-%d:%H:%M:%S')

MAILGUN_API_KEY = os.getenv("MAILGUN_API_KEY")
TOKEN_LIFE_MINUTES = 60

app = Flask(__name__)
app.secret_key = 'asd123asd12341asd123'
CORS(app, supports_credentials=True)
sslify = SSLify(app)


def token_required(f):
    @wraps(f)
    def decorated(*args,**kwargs):
        db = DB()
        token = None

        if 'x-access-token' in request.headers:
            token = request.headers['x-access-token']

        if not token:
            db.connection.close()
            return jsonify({
                "success": False,
                "message": "Token is missing!"
            }), 401

        try:
            data = jwt.decode(token,app.secret_key)
            # validate token life:
            life = data['exp']
            rnow = int(datetime.now().timestamp())
            if rnow > life:
                db.connection.close()
                # token no longer valid:
                return jsonify({
                    "message":"Token has expired. Please login again.",
                    "success": False
                }), 401
            current_user = db.get_user_by_email(data['email'])
            if is_admin({'email':data['email']}):
                current_user['admin'] = True

        except Exception as e:
            db.connection.close()
            return jsonify({
                "message": "Token is invalid. "+str(e),
                "success": False
            }), 401
        db.connection.close()
        if not current_user:
            return jsonify({
                    "message": "User is invalid",
                    "success": False
                }), 401
        return f(current_user,*args,**kwargs)
    return decorated

@app.route("/health")
def index():
    return jsonify({
        "success": True,
        "message": "All good"
    }),200



@app.route("/must_be_logged_in",methods=["GET"])
@token_required
def must_be_logged_in(current_user):
    return jsonify({
        "success": True,
        "message": "You are logged in!"
    }),200

@app.route("/login",methods=["GET","POST"])
def login():
    if request.method == "GET":
        email = request.args.get("email")
        if email:
            db = DB()
            user = db.get_user_by_email(email)
            if not user:
                db.connection.close()
                return jsonify({
                    "success": False,
                    "message": "User not found."
                })
            new_passcode = db.update_user_passcode(email)
            if not new_passcode:
                db.connection.close()
                return jsonify({
                    "success":False,
                    "message": "User not found."
                })
            db.connection.close()
            try:
                flag = send_passcode(email,user['first_name'],new_passcode)
                if flag:
                    return jsonify({
                        "success": True,
                        "message": "Passcode sent.",
                        "message_id": flag
                    })
                else:
                    return jsonify({
                        "success": False,
                        "message": "Could not send passcode."
                    })
            except Exception as e:
                logging.error(e)
                return jsonify({
                    "success": False,
                    "message": "There was an error sending passcode. "+str(e)
                }), 500

        else:
            return jsonify({
                "success": False,
                "message": "Email must be set."
            })
    elif request.method == "POST":
        # parse login data
        auth = request.authorization
        if not auth or not auth.username or not auth.password:
            return make_response('Could not verify',401, {'WWW-Authenticate': 'Basic realm="Login required"'})

        email = auth.username
        passcode = auth.password
        db = DB()
        result = db.login_user(email,passcode)
        if result['success']:
            token = generate_token(result['data'])
            db.connection.close()
            admin = is_admin(result['data'])
            return jsonify({
                "success": True,
                "message": "You are now logged in.",
                "token": token,
                "created_at": result['data']['created'].timestamp(),
                "first_name": result['data']['first_name'],
                "last_name": result['data']['last_name'],
                "user_id": result['data']['id'],
                "admin": admin
            })
        else:
            
            if result['error'] == 102:
                # send mailgun
                # send_mailgun(email,result['data']['new_passcode'])
                user = db.get_user_by_email(email)
                db.connection.close()
                try:
                    flag = send_passcode(email,user['first_name'],result['data']['new_passcode'])
                    if flag:
                        return jsonify({
                            "success": True,
                            "message": "Passcode sent.",
                            "message_id": flag
                        })
                    else:
                        return jsonify({
                            "success": False,
                            "message": "Could not send passcode."
                        })
                except Exception as e:
                    logging.error(e)
                    return jsonify({
                        "success": False,
                        "message": "There was an error sending passcode. "+str(e)
                    }), 500
                
            if result['error']:
                return make_response('Could not verify',401, {'WWW-Authenticate': 'Basic realm="Login required"'})
def is_admin(user_data):
    email = user_data['email']
    domain = email[email.rfind("@")+1:]
    if domain == "company.com":
        return True
    return False

@app.route("/renew-token", methods=["GET"])
@token_required
def renew_token(current_user):
    token = generate_token(current_user)
    
    return jsonify({
        "token": token,
        "success": True,
        "created_at": current_user['created'].timestamp(),
        "first_name": current_user['first_name'],
        "last_name": current_user['last_name'],
        "user_id": current_user['id'],
        "admin": current_user['admin']
    }), 200


def generate_token(user):
    exp = int((datetime.now() + timedelta(minutes=TOKEN_LIFE_MINUTES)).timestamp())
    if 'admin' in user and user['admin']:
        token = jwt.encode({'email':user['email'],'exp':exp,"admin":True},app.secret_key)
    else:
        token = jwt.encode({'email':user['email'],'exp':exp},app.secret_key)
    return token

def send_passcode(to_email, template, subject):
    # r = requests.post(
    #     "https://api.mailgun.net/v3/mg.company.com/messages",
    #     auth=("api", MAILGUN_API_KEY),
    #     data={"from": "Company<mailgun@mg.company.com>",
    #         "to": [to_email],
    #         "subject": subject,
    #         "html": template
    # })
    # return r.json()['id'].replace('<','').replace('>','')

    # Placeholder
    return "secret_message_id"


if __name__ == "__main__":
        app.run(debug=True,port=5050)



EOF
cat <<EOF >.env
DATABASE_URL=postgres://postgres:secret@localhost:5432/flask_sample5
EOF
mkdir modules
mkdir sql
mkdir temp
mkdir bin

cd modules
touch __init__.py
cat <<EOF >db.py
import psycopg2, psycopg2.extras
from datetime import datetime
import os
import json
import uuid
import urllib.parse
import string
import random
import traceback
import logging
from dotenv import load_dotenv

load_dotenv()


logging.basicConfig(level=logging.INFO, format='%(asctime)s,%(msecs)d %(levelname)-8s [%(filename)s:%(lineno)d] %(message)s', datefmt='%Y-%m-%d:%H:%M:%S')

PASSCODE_DURATION_MINUTES = 15

class DB():

    ERROR_CODES = {
            100: "User does not exist",
            101: "Passcode does not match.",
            102: "Passcode expired."
        }

    def __init__(self):
        urllib.parse.uses_netloc.append("postgres")
        url = urllib.parse.urlparse(os.getenv("DATABASE_URL"))

        self.connection = psycopg2.connect(
            database=url.path[1:],
            user=url.username,
            password=url.password,
            host=url.hostname,
            port=url.port
        )


    # Returns a dict cursor
    def get_cursor(self):
        return self.connection.cursor(cursor_factory=psycopg2.extras.DictCursor)


    def get_user(self,_id):
        cursor = self.get_cursor()
        cursor.execute("SELECT * FROM users WHERE id=%s",[_id])
        row = cursor.fetchone()
        if row:
            return dict(row)
        return False

    def get_users(self):
        cursor = self.get_cursor()
        cursor.execute("SELECT * FROM users ORDER BY id ASC")
        rows = cursor.fetchall()
        users = []
        for row in rows:
            users.append(dict(row))
        return users

    def get_user_by_email(self,email):
        cursor = self.get_cursor()
        # check if email exists:
        cursor.execute("SELECT * FROM users WHERE email=%s LIMIT 1",[email])
        row = cursor.fetchone()
        if row:
            return dict(row)
        return False

    def create_user(self,email,first_name,last_name):
        passcode = self.create_passcode()
        cursor = self.get_cursor()
        # check if email exists:
        user = self.get_user_by_email(email)
        if user:
            return False

        cursor.execute("INSERT INTO users (first_name,last_name,email,passcode,passcode_created) VALUES (%s,%s,%s,%s,%s)",[first_name,last_name,email,passcode,datetime.now()])
        self.connection.commit()
        return passcode

    def delete_user(self,user_id):
        cur = self.get_cursor()
        cur.execute("DELETE FROM users WHERE id=%s",[user_id])
        self.connection.commit()
        return True

    def login_user(self,email,passcode,passcode_bypass=False):
        cursor = self.get_cursor()
        cursor.execute("SELECT * FROM users WHERE email = %s",[email])
        row = cursor.fetchone()
        if not row:
            return {
                "success": False,
                "error" : 100
            }
        user = dict(row)
        if not passcode_bypass:
            passcode_created = user['passcode_created']
            timediff = datetime.now() - passcode_created
            if timediff.seconds / 60 <= PASSCODE_DURATION_MINUTES:
                # Passcode still valid:
                if passcode != user['passcode']:
                    return {
                        "success" : False,
                        "error" : 101
                    }
                # update last_seen
                cursor.execute("UPDATE users SET last_seen=%s WHERE email=%s",[datetime.now(),email])
                self.connection.commit()
                return {
                    "success": True,
                    "data": user
                }

            # passcode invalid
            
            new_passcode = self.update_user_passcode(email)
            return {
                "success" : False,
                "error": 102,
                "data": {
                    "new_passcode": new_passcode
                }
            }
        else:
            # update last_seen
            cursor.execute("UPDATE users SET last_seen=%s WHERE email=%s",[datetime.now(),email])
            self.connection.commit()
            return {
                "success": True,
                "data": user
            }


    def update_user_passcode(self,email,force_reset=False):
        cursor = self.get_cursor()
        if not force_reset:
            cursor.execute("SELECT * FROM users WHERE email=%s",[email])
            user = cursor.fetchone()
            if not user:
                return False
            current_passcode = user['passcode']
            current_passcode_created = user['passcode_created']
            now = datetime.now()
            delta = (now - current_passcode_created).total_seconds()
            if delta <= 60:
                return current_passcode

        passcode = self.create_passcode()
        cursor.execute("UPDATE users SET passcode=%s, passcode_created=%s WHERE email=%s RETURNING id",[passcode,datetime.now(),email])
        self.connection.commit()
        _id = False
        result = cursor.fetchone()
        if result:
            _id = result[0]
        if _id:
            return passcode
        else:
            return False


    def create_passcode(self):
        size = 6
        return ''.join(random.choices(string.digits, k=size))


EOF

cd ..
cd sql
cat <<EOF >schema.sql
CREATE TABLE users (id SERIAL PRIMARY KEY, first_name varchar(250), last_name VARCHAR(250),  email VARCHAR(200) NOT NULL UNIQUE, passcode VARCHAR(100), created TIMESTAMP NOT NULL DEFAULT NOW(), passcode_created TIMESTAMP, last_seen TIMESTAMP DEFAULT now());


INSERT INTO users (first_name,last_name,email,passcode,passcode_created,last_seen) VALUES ('Matias','Garafoni','matias.garafoni@gmail.com',12345,NOW(),NOW());
EOF

cd ..
cd temp
touch .gitkeep
cd ..

cat <<EOF >coverageme.sh
source venv/bin/activate
coverage run tests.py || exit 1
coverage xml
coverage lcov
coverage html
genbadge coverage -i - < coverage.xml
EOF

cat <<EOF >tests.py
import traceback
import unittest, os, json, io
from __init__ import app as client_app
import requests
from base64 import b64encode
from datetime import datetime


from modules.db import DB



class Tests(unittest.TestCase):
    def __init__(self):
        super().__init__()
        client_app.debug = True
        self.client = client_app.test_client()
        self.token = ""
        self.user_id = -1

    def test_1_get_health(self):
        r = self.client.get("/health")
        print(r.data)
        r_json = json.loads(r.data)
        self.assertEqual(r.status_code,200)
        self.assertEqual(r_json['success'],True)
        print("Test 1 Completed.")


    def test_2_login(self,email,sleep_=15):
        r = self.client.get("/login?email="+str(email.replace("+","%2B")))
        r_json = json.loads(r.data)
        print(r_json)
        self.assertEqual(r_json['success'],True)
        
        db = DB()
        user = db.get_user_by_email(email)
        db.connection.close()
        if user:
            passcode = user['passcode']
        else:
            print("Could not find user")
            self.assertEqual(True,False)

        credentials = b64encode((email+":"+str(passcode)).encode("utf-8")).decode('utf-8')
        r = self.client.post("/login",headers={"Authorization": f"Basic {credentials}"})
        print(r)
        r_json = json.loads(r.data)
        print(r_json)
        self.token = r_json['token']
        self.user_id = r_json['user_id']
        print(self.token)

        print("Test 2 Completed.")

if __name__ == "__main__":
    tester = Tests()
    tester.test_1_get_health()
    tester.test_2_login(email="matias.garafoni@gmail.com")
EOF

git init
cat <<EOF >.gitignore
.vscode
venv
_labs
*.pyc
__pycache__
temp/*
!temp/.gitkeep
EOF

cat <<EOF >README.md
# Welcome to flaskinit
[![Coverage Status](./coverage-badge.svg?dummy=8484744)](./coverage.xml)
## Description
Flask init is a shell script that creates a basic project structure, with a few dependencies within a virtualenv folder, using python3.6 (which you need to have installed previously, along with virtualenv)
If you can't execute the script, use $ \`chmod +x ./flaskinit.sh\` to provide the script with executable permissions. No sudo permissions are required.
## Requirements
* python3.x 
* python venv module
* PostgreSQL server
## Usage
After you execute the script, you will have a folder containing all the project structure and files. The file \`__init__.py\` on the root folder will be the "flask app file". It comes with a default route and some basic stuff to get you started quickly into adding more routes. Even if the script is meant to generate a squeleton for a Rest API, the templates and static folders are also created just in case you want to do a HTML response application.
The structure is made so that you include all your custom classes inside the modules folder, and all your "execute" files inside the bin folder.
To start the flask app, just activate the virtualenv by doing \`source venv/bin/activate\` and then starting the flask app with \`python __init__.py\`
EOF
read -p "Press enter to exit" continue