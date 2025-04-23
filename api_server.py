from flask import Flask, jsonify, request
import sys
import traceback
import os
import logging

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "healthy"})

@app.route("/")
def home():
    try:
        import zipline
        version = zipline.__version__
    except Exception as e:
        error_msg = str(e)
        traceback_str = traceback.format_exc()
        logger.error(f"Error importing zipline: {error_msg}")
        logger.error(traceback_str)
        return jsonify({
            "message": "Zipline API Server",
            "error": error_msg,
            "traceback": traceback_str
        }), 500
    
    return jsonify({
        "message": "Zipline API Server",
        "version": version
    })

if __name__ == "__main__":
    try:
        logger.info("Starting Zipline API Server...")
        logger.info(f"ZIPLINE_ROOT: {os.environ.get('ZIPLINE_ROOT', 'Not set')}")
        logger.info(f"Current directory: {os.getcwd()}")
        
        # Try importing zipline to see if it works
        import zipline
        logger.info(f"Zipline version: {zipline.__version__}")
        
        app.run(host="0.0.0.0", port=8081, debug=True)
    except Exception as e:
        logger.error(f"Error starting server: {e}")
        logger.error(traceback.format_exc())
        sys.exit(1)
