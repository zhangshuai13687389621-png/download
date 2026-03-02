import tiktoken
import os

print(f"TIKTOKEN_CACHE_DIR={os.environ.get('TIKTOKEN_CACHE_DIR')}")
try:
    tiktoken.get_encoding('cl100k_base')
    print("Success")
except Exception as e:
    print(f"Error: {e}")
