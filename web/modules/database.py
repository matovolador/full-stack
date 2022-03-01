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
            user = db.query(self).filter_by(email=email).first()
            if not user:
                return False
        if not force_reset:
            print(user)
            current_passcode = user.passcode
            current_passcode_created = user.passcode_created
            now = datetime.now()
            delta = (now - current_passcode_created).total_seconds()
            if delta <= PASSCODE_DURATION_MINUTES:
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