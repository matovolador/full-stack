from sqlalchemy import Integer, String
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
    