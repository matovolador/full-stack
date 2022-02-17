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
        url = urllib.parse.urlparse(os.get_env("DATABASE_URL"))

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
        cursor.execute("SELECT * FROM users WHERE email = %s and disabled=FALSE",[email])
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
        cursor.execute("UPDATE users SET passcode=%s, passcode_created=%s WHERE email=%s AND disabled=FALSE RETURNING id",[passcode,datetime.now(),email])
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

