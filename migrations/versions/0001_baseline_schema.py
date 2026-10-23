"""baseline schema: every table as it was when migrations were introduced (Oct 2026)

Revision ID: 0001
Revises: 
Created: 2026-10-23 12:59:13.043703
"""
from alembic import op
import sqlalchemy as sa


revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('employees',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('username', sa.String(length=50), nullable=False),
    sa.Column('password', sa.String(length=255), nullable=False),
    sa.Column('role', sa.String(length=10), nullable=True),
    sa.Column('category', sa.String(length=30), nullable=True),
    sa.Column('is_active', sa.Boolean(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=True),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('username')
    )
    with op.batch_alter_table('employees', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_employees_id'), ['id'], unique=False)

    op.create_table('holidays',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('date', sa.Date(), nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('date')
    )
    op.create_table('notices',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('title', sa.String(length=120), nullable=False),
    sa.Column('body', sa.Text(), nullable=True),
    sa.Column('pinned', sa.Boolean(), nullable=False),
    sa.Column('expires_on', sa.Date(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('created_by', sa.String(length=100), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('settings',
    sa.Column('key', sa.String(length=50), nullable=False),
    sa.Column('value', sa.Text(), nullable=False),
    sa.PrimaryKeyConstraint('key')
    )
    op.create_table('attendance_logs',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('employee_id', sa.Integer(), nullable=False),
    sa.Column('date', sa.String(length=20), nullable=False),
    sa.Column('in_time', sa.DateTime(), nullable=True),
    sa.Column('out_time', sa.DateTime(), nullable=True),
    sa.Column('status', sa.String(length=10), nullable=True),
    sa.Column('auto_checkout', sa.Boolean(), nullable=False),
    sa.ForeignKeyConstraint(['employee_id'], ['employees.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('attendance_logs', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_attendance_logs_id'), ['id'], unique=False)
        batch_op.create_index('uq_attendance_employee_date', ['employee_id', 'date'], unique=True)

    op.create_table('audit_logs',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('at', sa.DateTime(), nullable=False),
    sa.Column('actor_id', sa.Integer(), nullable=True),
    sa.Column('actor_name', sa.String(length=100), nullable=False),
    sa.Column('action', sa.String(length=50), nullable=False),
    sa.Column('employee_id', sa.Integer(), nullable=True),
    sa.Column('details', sa.Text(), nullable=True),
    sa.Column('reason', sa.Text(), nullable=True),
    sa.ForeignKeyConstraint(['actor_id'], ['employees.id'], ),
    sa.ForeignKeyConstraint(['employee_id'], ['employees.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('audit_logs', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_audit_logs_at'), ['at'], unique=False)

    op.create_table('correction_requests',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('employee_id', sa.Integer(), nullable=False),
    sa.Column('date', sa.Date(), nullable=False),
    sa.Column('kind', sa.String(length=30), nullable=False),
    sa.Column('note', sa.Text(), nullable=True),
    sa.Column('status', sa.String(length=10), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=True),
    sa.Column('resolved_at', sa.DateTime(), nullable=True),
    sa.ForeignKeyConstraint(['employee_id'], ['employees.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('correction_requests', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_correction_requests_employee_id'), ['employee_id'], unique=False)

    op.create_table('face_images',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('employee_id', sa.Integer(), nullable=False),
    sa.Column('image_path', sa.String(length=255), nullable=False),
    sa.Column('direction', sa.String(length=10), nullable=False),
    sa.Column('embedding', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=True),
    sa.ForeignKeyConstraint(['employee_id'], ['employees.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('face_images', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_face_images_id'), ['id'], unique=False)

    op.create_table('leave_requests',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('employee_id', sa.Integer(), nullable=False),
    sa.Column('start_date', sa.Date(), nullable=False),
    sa.Column('end_date', sa.Date(), nullable=False),
    sa.Column('kind', sa.String(length=20), nullable=False),
    sa.Column('reason', sa.Text(), nullable=True),
    sa.Column('status', sa.String(length=10), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=True),
    sa.Column('decided_at', sa.DateTime(), nullable=True),
    sa.Column('decided_by', sa.Integer(), nullable=True),
    sa.ForeignKeyConstraint(['decided_by'], ['employees.id'], ),
    sa.ForeignKeyConstraint(['employee_id'], ['employees.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('leave_requests', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_leave_requests_employee_id'), ['employee_id'], unique=False)



def downgrade() -> None:
    with op.batch_alter_table('leave_requests', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_leave_requests_employee_id'))

    op.drop_table('leave_requests')
    with op.batch_alter_table('face_images', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_face_images_id'))

    op.drop_table('face_images')
    with op.batch_alter_table('correction_requests', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_correction_requests_employee_id'))

    op.drop_table('correction_requests')
    with op.batch_alter_table('audit_logs', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_audit_logs_at'))

    op.drop_table('audit_logs')
    with op.batch_alter_table('attendance_logs', schema=None) as batch_op:
        batch_op.drop_index('uq_attendance_employee_date')
        batch_op.drop_index(batch_op.f('ix_attendance_logs_id'))

    op.drop_table('attendance_logs')
    op.drop_table('settings')
    op.drop_table('notices')
    op.drop_table('holidays')
    with op.batch_alter_table('employees', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_employees_id'))

    op.drop_table('employees')
