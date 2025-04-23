#!/usr/bin/env python

# Find the problematic file
import os
import sys

alembic_env_path = None
for root, dirs, files in os.walk('/opt/conda/envs/zipline/lib/python3.6/site-packages/alembic'):
    if 'environment.py' in files:
        alembic_env_path = os.path.join(root, 'environment.py')
        break

if not alembic_env_path:
    print("Could not find alembic environment.py")
    sys.exit(1)

# Read the file
with open(alembic_env_path, 'r') as f:
    content = f.read()

# Replace the problematic import
if 'from __future__ import annotations' in content:
    content = content.replace('from __future__ import annotations', '')
    
    # Write the file back
    with open(alembic_env_path, 'w') as f:
        f.write(content)
    
    print(f"Successfully patched {alembic_env_path}")
else:
    print(f"No need to patch {alembic_env_path}")
