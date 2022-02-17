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

