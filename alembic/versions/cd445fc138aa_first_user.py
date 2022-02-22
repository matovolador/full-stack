"""first_user

Revision ID: cd445fc138aa
Revises: 355b9905a33f
Create Date: 2022-02-22 16:44:09.538359

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'cd445fc138aa'
down_revision = '355b9905a33f'
branch_labels = None
depends_on = None


def upgrade():
    op.execute("INSERT INTO users (first_name,last_name,email,created,passcode,passcode_created,last_seen) VALUES ('Matias','Garafoni','matias.garafoni@gmail.com',NOW(),'12345',NOW(),NOW())")


def downgrade():
    op.execute("DELETE FROM users WHERE email='matias.garafoni@gmail.com'")
