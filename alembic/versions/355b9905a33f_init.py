"""init

Revision ID: 355b9905a33f
Revises: 
Create Date: 2022-02-21 23:55:53.971143

"""
from alembic import op
import sqlalchemy as sa
import datetime

# revision identifiers, used by Alembic.
revision = '355b9905a33f'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'users',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('first_name', sa.String, nullable=False),
        sa.Column('last_name', sa.String, nullable=False),
        sa.Column('email',sa.String,nullable=False),
        sa.Column('created',sa.DateTime(timezone=False),nullable=False, default=sa.func.now()),
        sa.Column('last_seen',sa.DateTime(timezone=False), default=sa.func.now()),
        sa.Column('passcode',sa.String),
        sa.Column('passcode_created',sa.DateTime(timezone=False),nullable=False),
    )


def downgrade():
    op.drop_table('users')