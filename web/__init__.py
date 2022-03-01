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
# sslify = SSLify(app)


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
        app.run(host='0.0.0.0',debug=os.getenv("DEBUG"),port=5050)

