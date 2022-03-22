"""Users table

Revision ID: 503b0a20587b
Revises: 
Create Date: 2022-03-21 14:46:33.265387

"""
from alembic import op
import sqlalchemy as sa
import datetime


# revision identifiers, used by Alembic.
revision = '503b0a20587b'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'users',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('username',sa.String,nullable=False,unique=True),
        sa.Column('email',sa.String,nullable=False,unique=True),
        sa.Column('first_name',sa.String,nullable=True),
        sa.Column('last_name',sa.String,nullable=True),
        sa.Column('created',sa.DateTime(timezone=False),nullable=False, default=sa.func.now()),
        sa.Column('last_seen',sa.DateTime(timezone=False), default=sa.func.now()),
        sa.Column('password',sa.String),
        sa.Column('password_created',sa.DateTime(timezone=False),nullable=False),
        sa.Column('email_validated',sa.Boolean,nullable=False,default=False),
        sa.Column('email_validation_token',sa.String,nullable=True,default=None),
        sa.Column('email_validation_token_created',sa.DateTime(timezone=False),nullable=True,default=None),
        sa.Column('access_level',sa.Integer,nullable=False,default=0),
        sa.Column('token',sa.String,nullable=True,default=None)

    )


def downgrade():
    op.drop_table('users')
