#!/bin/bash
read -p "Enter project path: " path
mkdir -p $path
cd $path
python3 -m venv venv
source venv/bin/activate
pip install wheel || exit 1
pip install flask flask_cors flask_sslify mypy psycopg2 psycopg2-binary requests PyJWT python-dotenv coverage genbadge defusedxml SQLAlchemy alembic gunicorn || exit 1
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
from modules.database import get_db
import modules.models as models

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
            data = jwt.decode(token,app.secret_key,algorithms="HS256")
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


def is_empty_string_or_none(_str):
    if _str == '' or _str is None:
        return True
    return False

@app.route("/books/<book_id>",methods=["GET"])
@app.route("/books",defaults={"book_id":None},methods=["POST"])
@token_required
def books(current_user,book_id):
    if request.method=="POST":
        data = request.get_json()
        if 'author' not in data or 'name' not in data or is_empty_string_or_none(data['author']) or is_empty_string_or_none(data['name']):
            return jsonify({
                "success": False,
                "message": "Missing params"
            })
        db = next(get_db())
        book = models.Book(name=data['name'],author=data['author'])
        db.add(book)
        db.commit()
        user_book_assoc = models.UserBookAssociation(user_id=current_user['id'],book_id=book.id)
        db.add(user_book_assoc)
        db.commit()
        return jsonify({
            "success":True,
            "id": book.id
        })
    elif request.method=="GET":
        db = next(get_db())
        book = db.query(models.Book).get(int(book_id))
        # confirm that book belongs to current user
        assoc = db.query(models.UserBookAssociation).filter_by(user_id=current_user['id'],book_id=int(book_id))
        if not assoc:
            return jsonify({
                "success":False,
                "message": "This user does not have this book."
            })
        return jsonify({
            "success": True,
            "book": book.as_dict()
        })
        

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
        token = jwt.encode({'email':user['email'],'exp':exp,"admin":True},app.secret_key,algorithm="HS256")
    else:
        token = jwt.encode({'email':user['email'],'exp':exp},app.secret_key,algorithm="HS256")
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
DATABASE_URL=postgresql://postgres:secret@localhost:5432/flask_sample5
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

cat <<EOF >database.py
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
from dotenv import load_dotenv

load_dotenv()

SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    except:
        db.close()
EOF

cat <<EOF >models.py
from sqlalchemy import Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql.schema import Column
from sqlalchemy.sql import func
from .database import Base

class BaseMixin(object):
    def as_dict(self):
       return {c.name: getattr(self, c.name) for c in self.__table__.columns}


class User(BaseMixin,Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    email = Column(String, nullable=False)
    created = Column(DateTime(),nullable=False, default=func.now())
    last_seen = Column(DateTime(),default=func.now())
    passcode = Column(Integer)
    passcode_created = Column(DateTime(),nullable=False)


class Book(BaseMixin,Base):
    __tablename__ = 'books'

    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    author = Column(String, nullable=False)


class UserBookAssociation(BaseMixin,Base):
    __tablename__ = 'user_book_associations'

    id = Column(Integer,primary_key=True)
    user_id = Column(Integer,ForeignKey('users.id'))
    book_id = Column(Integer,ForeignKey('books.id'))
    
    
EOF
cd ..

alembic init alembic

echo "from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context
import os
from dotenv import load_dotenv

load_dotenv()


# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

config.set_main_option('sqlalchemy.url', os.getenv('DATABASE_URL'))

# Interpret the config file for Python logging.
# This line sets up loggers basically.
fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
# from myapp import mymodel
# target_metadata = mymodel.Base.metadata
target_metadata = None

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option('my_important_option')
# ... etc.


def run_migrations_offline():
    #Run migrations in 'offline' mode.
    #
    #This configures the context with just a URL and not an Engine, though an Engine is acceptable here as well.  By skipping the Engine creation we don't even need a DBAPI to be available.
    #
    #Calls to context.execute() here emit the given string to the script output.

    url = config.get_main_option('sqlalchemy.url')
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={'paramstyle': 'named'},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    #Run migrations in 'online' mode.
    #
    #In this scenario we need to create an Engine and associate a connection with the context.

    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix='sqlalchemy.',
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
" >| "./alembic/env.py"

cd alembic/versions
cat <<EOF >355b9905a33f_init.py
"""init

Revision ID: 355b9905a33f
Revises: 
Create Date: 2022-02-21 23:55:53.971143

"""
from alembic import op
import sqlalchemy as sa
import datetime

# revision identifiers, used by Alembic.
revision = '355b9905a33f'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'users',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('first_name', sa.String, nullable=False),
        sa.Column('last_name', sa.String, nullable=False),
        sa.Column('email',sa.String,nullable=False),
        sa.Column('created',sa.DateTime(timezone=False),nullable=False, default=sa.func.now()),
        sa.Column('last_seen',sa.DateTime(timezone=False), default=sa.func.now()),
        sa.Column('passcode',sa.String),
        sa.Column('passcode_created',sa.DateTime(timezone=False),nullable=False),
    )


def downgrade():
    op.drop_table('users')
EOF

cat <<EOF >cd445fc138aa_first_user.py
"""first_user

Revision ID: cd445fc138aa
Revises: 355b9905a33f
Create Date: 2022-02-22 16:44:09.538359

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'cd445fc138aa'
down_revision = '355b9905a33f'
branch_labels = None
depends_on = None


def upgrade():
    op.execute("INSERT INTO users (first_name,last_name,email,created,passcode,passcode_created,last_seen) VALUES ('Matias','Garafoni','matias.garafoni@gmail.com',NOW(),'12345',NOW(),NOW())")


def downgrade():
    op.execute("DELETE FROM users WHERE email='matias.garafoni@gmail.com'")
EOF

cat <<EOF >c5e1c4373b3d_books.py
"""books

Revision ID: c5e1c4373b3d
Revises: cd445fc138aa
Create Date: 2022-02-22 18:03:51.814438

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c5e1c4373b3d'
down_revision = 'cd445fc138aa'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'books',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('name', sa.String, nullable=False),
        sa.Column('author', sa.String, nullable=False)
    )
    op.create_table(
        'user_book_associations',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('user_id', sa.Integer,sa.ForeignKey('users.id')),
        sa.Column('book_id', sa.Integer,sa.ForeignKey('books.id'))
    )
     

def downgrade():
    op.drop_table('user_book_associations')
    op.drop_table('books')
EOF

cd ../..
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
import random
import string



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

    def test_3_can_access(self):
        r = self.client.get("/must_be_logged_in", headers={"x-access-token":str(self.token)})
        r_json = json.loads(r.data)
        print(r_json)
        self.assertEqual(r_json['success'],True)
        print("Test 3 completed.")

    def test_4_create_book(self,author,name,should_fail=False):
        r = self.client.post("/books",headers={
            "x-access-token":str(self.token),
            "Content-Type": "application/json"
            },data=json.dumps({
            "author": author,
            "name": name
        }))
        r_json = json.loads(r.data)
        print(r_json)
        
        self.assertEqual(r_json['success'],not should_fail)
        print("Test 4 completed.")
        if not should_fail:
            return r_json['id']
        else:
            return

    def test_5_get_book(self,book_id):
        r = self.client.get("/books/"+str(book_id), headers={"x-access-token":str(self.token)})
        print(r)
        print(r.data)
        r_json = json.loads(r.data)
        print(r_json)
        self.assertEqual(r_json['success'],True)
        print("Test 3 completed.")

if __name__ == "__main__":
    tester = Tests()
    tester.test_1_get_health()
    tester.test_2_login(email="matias.garafoni@gmail.com")
    tester.test_3_can_access()
    # printing lowercase
    letters = string.ascii_lowercase
    rand_author = ''.join(random.choice(letters) for i in range(10)) + "_author"
    rand_bookname = ''.join(random.choice(letters) for i in range(10)) + "_bookname"
    book_id = tester.test_4_create_book(author=rand_author,name=rand_bookname)
    tester.test_5_get_book(book_id=book_id)
    tester.test_4_create_book(author='',name='',should_fail=True)
EOF

source venv/bin/activate
alembic upgrade head

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