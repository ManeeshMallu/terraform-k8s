import json
import random

def handler(event, context):
    # default to a 6-sided die
    sides = 6

    # Parse custom sides from query parameters if they exist
    query_params = event.get("queryStringParameters")
    if query_params and "sides" in query_params:
        try:
            sides = int(query_params["sides"])
            if sides < 1:
                sides = 6
        except ValueError:
            pass # Fall back to 6 if parsing fails
    
    roll = random.randint(1, sides)

    body = {
        "sides": sides,
        "result": roll,
        "message": f"You rolled a d{sides} and got a {roll}!"
    }

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(body)
    }
