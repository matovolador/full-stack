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