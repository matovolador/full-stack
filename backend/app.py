from flask import Flask, request,jsonify, make_response, render_template, send_from_directory
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


TOKEN_LIFE_MINUTES = 15

app = Flask(__name__)
app.secret_key = 'asd123asd12341asd123'
CORS(app, supports_credentials=True)
# sslify = SSLify(app)


def generate_token(user):
    exp = int((datetime.now() + timedelta(minutes=TOKEN_LIFE_MINUTES)).timestamp())
    token = jwt.encode({'email':user['email'],'exp':exp},app.secret_key,algorithm="HS256")
    return token


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
            if not current_user:
                current_user = db.query(database.User).filter_by(username=data['email']).first()
            print(current_user.token)
            if current_user.token is None:
                return jsonify({
                    "success": False,
                    "message": "You must login."
                }),401
            if current_user.token != token:
                return jsonify({
                    "success": False,
                    "message": "Token invalid."
                }),401
            current_user = current_user.as_dict()
            

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

@app.route("/api/health/")
def index():
    return jsonify({
        "success": True,
        "message": "All good"
    }),200

@app.route("/api/must_be_logged_in/",methods=["GET"])
@token_required
def must_be_logged_in(current_user):
    print(current_user)
    return jsonify({
        "success": True,
        "message": "You are logged in!"
    }),200


@app.route("/api/login/",methods=["POST"])
def login():
    auth = request.authorization
    if not auth or not auth.username or not auth.password:
        return make_response('Could not verify',401, {'WWW-Authenticate': 'Basic realm="Login required"'})

    email_or_username = auth.username
    password = auth.password
    result, data = database.User.login_user(email_or_username=email_or_username,password=password)
    print(result)
    print(data)
    if result:
        db = next(database.get_db())
        token = generate_token(data)
        user = db.query(database.User).get(data['id'])
        user.token = token
        db.commit()
        return jsonify({
            "success": True,
            "message": "You are now logged in.",
            "token": token,
            "user_id": user.id
        })
    else:
        return jsonify({
            "success":False,
            "message": str(data)
        }),401

@app.route("/api/logout/",methods=["GET","POST"])
@token_required
def logout(current_user):
    db = next(database.get_db())
    user = db.query(database.User).get(current_user['id'])
    user.token = None
    db.commit()
    return jsonify({
        "success":True
    })

@app.route("/api/registration/",methods=["POST"])
def register():
    username = request.values.get("username")
    email = request.values.get("email")
    password = request.values.get("password")
    first_name = request.values.get("first_name",None)
    last_name = request.values.get("last_name")
    db = next(database.get_db())
    user = db.query(database.User).filter_by(username=username).first()
    if user:
        return jsonify({
            "success": False,
            "message": "Username already taken."
        })
    user = db.query(database.User).filter_by(email=email).first()
    if user:
        return jsonify({
            "success": False,
            "message": "Email already taken."
        })
    try:
        user = database.User(username=username,email=email,password=password,first_name=first_name,last_name=last_name)
        db.add(user)
        db.commit()
        clean_user = user.retrieve_clean_user_data(user.id)
        return jsonify({
            "success": True,
            "data": clean_user
        })
    except Exception as e:
        return jsonify({
            "success": False,
            "message": "Exception "+str(e)
        })

    


@app.route("/api/renew-token/", methods=["GET"])
@token_required
def renew_token(current_user):
    token = generate_token(current_user)
    db = next(database.get_db())
    user = db.query(database.User).filter_by(username=current_user['username']).first()
    user.token = token
    db.commit()
    return jsonify({
        "token": token,
        "success": True
    }), 200


if __name__ == "__main__":
    app.run(host='0.0.0.0',debug=True,port=5050)
