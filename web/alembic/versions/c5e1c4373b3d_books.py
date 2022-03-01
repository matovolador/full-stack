"""books

Revision ID: c5e1c4373b3d
Revises: cd445fc138aa
Create Date: 2022-02-22 18:03:51.814438

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c5e1c4373b3d'
down_revision = 'cd445fc138aa'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'books',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('name', sa.String, nullable=False),
        sa.Column('author', sa.String, nullable=False)
    )
    op.create_table(
        'user_book_associations',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('user_id', sa.Integer,sa.ForeignKey('users.id')),
        sa.Column('book_id', sa.Integer,sa.ForeignKey('books.id'))
    )
     

def downgrade():
    op.drop_table('user_book_associations')
    op.drop_table('books')
