from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy import Integer, String, DateTime, ForeignKey, Boolean
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
    email = Column(String, nullable=False,unique=True)
    username = Column(String,nullable=False,unique=True)
    first_name = Column(String,nullable=True,default=None)
    last_name = Column(String,nullable=True,default=None)
    created = Column(DateTime(),nullable=False, default=func.now())
    last_seen = Column(DateTime(),default=func.now())
    password = Column(String)
    password_created = Column(DateTime(),nullable=False)
    access_level = Column(Integer, nullable=False, default=0)
    email_validated = Column(Boolean,nullable=False,default=False)
    email_validation_token = Column(String,nullable=True,default=None)
    email_validation_token_created = Column(DateTime(),nullable=True, default=None)
    token = Column(String,nullable=True,default=None)


    @classmethod
    def retrieve_clean_user_data(self,include_token = True):
        if include_token:
            return {
                "id": self.id,
                "username": self.username,
                "email": self.email,
                "token": self.token,
                "first_name": self.first_name,
                "last_name": self.last_name
            }, ""
        else: 
            return {
                "id": self.id,
                "username": self.username,
                "email": self.email,
                "first_name": self.first_name,
                "last_name": self.last_name
            }, ""

    @staticmethod
    def login_user(email_or_username,password):
        db = next(get_db())
        user = False
        user = db.query(User).filter_by(email=email_or_username).first()
        if not user:
            user = db.query(User).filter_by(username=email_or_username).first()
        
        if not user:
            return False, "User not found."

        if user.password != password:
            return False, "Invalid password."

        if user.email_validated == False:
            return False, "You must first verify your email."
        
        user.last_seen = datetime.now()
        db.commit()
        return True, user.as_dict()


    @classmethod
    def update_user_password(self,password):
        db = next(get_db())
        self.password=password
        self.password_created = datetime.now()
        db.commit()
        return True
            
    @classmethod
    def generate_email_validation_token(self):
        db = next(get_db())
        if self.email_validated:
            return False, "Email already validated"
        size = 15
        self.email_validation_token = ''.join(random.choices(string.ascii_uppercase + string.digits, k = size))
        db.commit()
        return self.email_validation_token, ""

    @classmethod
    def validate_email(self,token):
        db = next(get_db())
        if self.email_validated:
            return False, "Email already validated"
        if self.email_validation_token == token:
            self.email_verified = True
            self.email_validation_token = None
            db.commit()
            return True, ""
        else:
            return False, "Email validation token is not correct"


