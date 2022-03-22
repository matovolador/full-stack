import traceback
import unittest, os, json, io
from app import app as client_app
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
        r = self.client.get("/api/health/")
        print(r.data)
        print(r.status_code)
        r_json = json.loads(r.data)
        self.assertEqual(r.status_code,200)
        self.assertEqual(r_json['success'],True)
        print("Test 1 Completed.")


    def test_2_login(self,email,password):
        credentials = b64encode((email+":"+str(password)).encode("utf-8")).decode('utf-8')
        r = self.client.post("/api/login/",headers={"Authorization": f"Basic {credentials}"})
        print(r)
        r_json = json.loads(r.data)
        print(r_json)
        self.token = r_json['token']
        self.user_id = r_json['user_id']
        print(self.token)

        print("Test 2 Completed.")

    def test_3_can_access(self,should_fail=False):
        r = self.client.get("/api/must_be_logged_in/", headers={"x-access-token":str(self.token)})
        r_json = json.loads(r.data)
        print(r_json)
        self.assertEqual(r_json['success'],not should_fail)
        print("Test 3 completed.")

    def test_4_logout(self):
        r = self.client.get("/api/logout/",headers={"x-access-token":str(self.token)})
        r_json = json.loads(r.data)
        print(r_json)
        self.assertEqual(r_json['success'],True)
        print("Test 4 completed")
        return

    def test_5_renew_token(self):
        r = self.client.get("/api/renew-token/", headers={"x-access-token":str(self.token)})
        r_json = json.loads(r.data)
        print(r_json)
        self.assertEqual(r_json['success'],True)
        self.token = r_json['token']
        print("Test 5 completed.")


if __name__ == "__main__":
    tester = Tests()
    tester.test_1_get_health()
    tester.test_2_login(email="matias.garafoni@gmail.com",password='1234')
    tester.test_3_can_access()
    tester.test_5_renew_token()
    tester.test_3_can_access()
    tester.test_4_logout()
    tester.test_3_can_access(should_fail=True)