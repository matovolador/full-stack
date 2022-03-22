"""test user

Revision ID: 036e5262ecee
Revises: 503b0a20587b
Create Date: 2022-03-22 14:46:32.317824

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '036e5262ecee'
down_revision = '503b0a20587b'
branch_labels = None
depends_on = None


def upgrade():
    op.execute("INSERT INTO users (username,email,password,password_created, created,email_validated,access_level) VALUES ('matovolador','matias.garafoni@gmail.com','1234',NOW(),NOW(),TRUE,6)")


def downgrade():
    op.execute("DELETE FROM users WHERE email='matias.garafoni@gmail.com'")
