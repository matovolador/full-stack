from sqlalchemy import Integer, String, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql.schema import Column
from sqlalchemy.sql import func
import datetime
from .database import Base


class User(Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    email = Column(String, nullable=False)
    created = Column(DateTime(),nullable=False, default=func.now())
    last_seen = Column(DateTime(),default=func.now())
    passcode = Column(Integer)
    passcode_created = Column(DateTime(),nullable=False)


class Book(Base):
    __tablename__ = 'books'

    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    author = Column(String, nullable=False)

class UserBookAssociation(Base):
    __tablename__ = 'user_book_associations'

    id = Column(Integer,primary_key=True)
    user_id = Column(Integer,ForeignKey('user.id'))
    book_id = Column(Integer,ForeignKey('book.id'))
    