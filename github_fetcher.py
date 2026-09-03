import requests

def get_github_repos(name, target_language):
    # define the url for a user's repos
    url = f"https://api.github.com/orgs/{name.lower()}/repos?per_page=100"
    print(f"Trying URL: {url}")
    response = requests.get(url)

    if response.status_code == 404:
        print(f"'{name}' is not an organization. Trying user endpoint...")
        url = f"https://github.com/{name.lower()}/repos?per_page=100"
        response = requests.get(url)

    # check if the request was successful (200)
    if response.status_code != 200:
        print(f"Error: Unable to fetch data. HTTP Status: {response.status_code}")
        return

    # convert the JSON response into the python list
    repos = response.json()

    print(f"Successfully found {len(repos)} total public repositories.\n")
    print(f"--- Repositories using primarily '{target_language}' ---")

    # Filter and print results
    matching_count = 0
    for repo in repos:
        # github API returns none if a repo has no primary language
        if repo.get('language') == target_language:
            print(f"Name: {repo['name']}")
            print(f"Stars: {repo['stargazers_count']}")
            print(f"URL: {repo['html_url']}")
            print("-" * 40)
            matching_count += 1

        if matching_count == 0:
            print(f"No repos found using '{target_language}' as the main lang")

# exec
if __name__ == "__main__":
    # prompt in the terminal
    user_input_name = input("Enter github Username or Org: ")
    user_input_lang = input("Enter programming language to filter by: ")

    get_github_repos(name=user_input_name, target_language=user_input_lang)
