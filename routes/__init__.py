# Routes Package - Flask Blueprints for HalllDay
# This package organizes app routes into logical modules

def register_blueprints(app):
    """Register all blueprints with the Flask app"""
    from .admin import admin_bp
    from .kiosk import kiosk_bp
    
    app.register_blueprint(admin_bp)
    app.register_blueprint(kiosk_bp)
