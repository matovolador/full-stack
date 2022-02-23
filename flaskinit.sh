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
import modules.database as database

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
        db = next(database.get_db())
        token = None

        if 'x-access-token' in request.headers:
            token = request.headers['x-access-token']

        if not token:
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
                # token no longer valid:
                return jsonify({
                    "message":"Token has expired. Please login again.",
                    "success": False
                }), 401
            current_user = db.query(database.User).filter_by(email=data['email']).first()
            current_user = current_user.as_dict()
            if is_admin({'email':data['email']}):
                current_user['admin'] = True

        except Exception as e:
            return jsonify({
                "message": "Token is invalid. "+str(e),
                "success": False
            }), 401
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
        db = next(database.get_db())
        book = database.Book(name=data['name'],author=data['author'])
        db.add(book)
        db.commit()
        user_book_assoc = database.UserBookAssociation(user_id=current_user['id'],book_id=book.id)
        db.add(user_book_assoc)
        db.commit()
        return jsonify({
            "success":True,
            "id": book.id
        })
    elif request.method=="GET":
        db = next(database.get_db())
        book = db.query(database.Book).get(int(book_id))
        # confirm that book belongs to current user
        assoc = db.query(database.UserBookAssociation).filter_by(user_id=current_user['id'],book_id=int(book_id)).first()
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
            db = next(database.get_db())
            user = db.query(database.User).filter_by(email=email).first()
            if not user:
                db.connection.close()
                return jsonify({
                    "success": False,
                    "message": "User not found."
                })
            new_passcode = database.User.update_user_passcode(email)
            if not new_passcode:
                return jsonify({
                    "success":False,
                    "message": "User not found."
                })
            try:
                flag = send_passcode(email,user.first_name,new_passcode)
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
        db = next(database.get_db())
        user = db.query(database.User).filter_by(email=email).first()
        result = database.User.login_user(email,passcode)
        if result['success']:
            token = generate_token(result['data'])
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
                try:
                    flag = send_passcode(email,user.first_name,result['data']['new_passcode'])
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

cat <<EOF >database.py
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy import Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql.schema import Column
from sqlalchemy.sql import func
from datetime import datetime
import string,random
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

PASSCODE_DURATION_MINUTES = 15

class BaseMixin(object):
    def as_dict(self):
       return {c.name: getattr(self, c.name) for c in self.__table__.columns}


class User(BaseMixin,Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    email = Column(String, nullable=False,unique=True)
    created = Column(DateTime(),nullable=False, default=func.now())
    last_seen = Column(DateTime(),default=func.now())
    passcode = Column(Integer)
    passcode_created = Column(DateTime(),nullable=False)

    @classmethod
    def login_user(self,email,passcode,passcode_bypass=False):
        db = next(get_db())
        user = db.query(self).filter_by(email=email).first()
        if not user:
            return {
                "success": False,
                "error" : 100 # "User does not exist"
            }
        passcode_created = user.passcode_created
        timediff = datetime.now() - passcode_created
        if timediff.seconds / 60 <= PASSCODE_DURATION_MINUTES:
            # Passcode still valid:
            if passcode != user.passcode:
                return {
                    "success" : False,
                    "error" : 101 # "Passcode does not match."
                }
            # update last_seen
            # update last_seen
            user.last_seen = datetime.now()
            db.commit()
            return {
                "success": True,
                "data": user.as_dict()
            }

        # passcode invalid
        
        new_passcode = self.update_user_passcode(email)
        return {
            "success" : False,
            "error": 102, # "Passcode expired."
            "data": {
                "new_passcode": new_passcode
            }
        }
        

    @classmethod
    def update_user_passcode(self,email,force_reset=False):
        db = next(get_db())
        if not force_reset:
            user = db.query(self).filter_by(email=email).first()
            if not user:
                return False
            print(user)
            current_passcode = user.passcode
            current_passcode_created = user.passcode_created
            now = datetime.now()
            delta = (now - current_passcode_created).total_seconds()
            if delta <= 60:
                return current_passcode

        passcode = self.create_passcode()
        user.passcode=passcode
        user.passcode_created = datetime.now()
        db.commit()
        return passcode
        
    @classmethod
    def create_passcode(self):
        size = 6
        return ''.join(random.choices(string.digits, k=size))


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
import modules.database as database


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
        
        db = next(database.get_db())
        user = db.query(database.User).filter_by(email=email).first()
        if user:
            passcode = user.passcode
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