"""birthdays, work anniversaries, one-day shift changes

Revision ID: 0002
Revises: 0001
Created: 2026-10-23 13:14:15.405590
"""
from alembic import op
import sqlalchemy as sa


revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('shift_changes',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('employee_id', sa.Integer(), nullable=False),
    sa.Column('date', sa.Date(), nullable=False),
    sa.Column('start', sa.String(length=5), nullable=False),
    sa.Column('end', sa.String(length=5), nullable=False),
    sa.Column('reason', sa.Text(), nullable=True),
    sa.Column('status', sa.String(length=10), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=True),
    sa.Column('decided_at', sa.DateTime(), nullable=True),
    sa.Column('decided_by', sa.Integer(), nullable=True),
    sa.ForeignKeyConstraint(['decided_by'], ['employees.id'], ),
    sa.ForeignKeyConstraint(['employee_id'], ['employees.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('shift_changes', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_shift_changes_employee_id'), ['employee_id'], unique=False)

    with op.batch_alter_table('employees', schema=None) as batch_op:
        batch_op.add_column(sa.Column('birthday', sa.Date(), nullable=True))
        batch_op.add_column(sa.Column('joined_on', sa.Date(), nullable=True))



def downgrade() -> None:
    with op.batch_alter_table('employees', schema=None) as batch_op:
        batch_op.drop_column('joined_on')
        batch_op.drop_column('birthday')

    with op.batch_alter_table('shift_changes', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_shift_changes_employee_id'))

    op.drop_table('shift_changes')
