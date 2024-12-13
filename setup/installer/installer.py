import typer, os, json, time, shutil, secrets, base64
from pathlib import Path
from typing import List
from dotenv import load_dotenv
from pprint import pprint
from rich import print as rprint


# High Level Configs

app = typer.Typer()
env_dir = Path(str(Path.home()) + '/selfhost/cursion/env')
env_client_old = Path(str(Path.home()) + '/selfhost/cursion/env/.client.example.env')
env_server_old = Path(str(Path.home()) + '/selfhost/cursion/env/.server.example.env')
env_client = Path(str(Path.home()) + '/selfhost/cursion/env/.client.env')
env_server = Path(str(Path.home()) + '/selfhost/cursion/env/.server.env')
cursion_root = 'https://api.cursion.dev'


SERVER_VARS = {
    
    # retrieved from user input
    'CLIENT_URL_ROOT'       : '',
    'API_URL_ROOT'          : '',
    'LETSENCRYPT_EMAIL'     : '',
    'LETSENCRYPT_HOST'      : '',
    'DEFAULT_EMAIL'         : '',
    'VIRTUAL_HOST'          : '',
    'ADMIN_PASS'            : '',
    'ADMIN_EMAIL'           : '',
    'LICENSE_KEY'           : '',
    
    # retrieved via API
    'GOOGLE_CRUX_KEY'               : '',
    'TWILIO_SID'                    : '',
    'TWILIO_AUTH_TOKEN'             : '',
    'SENDGRID_API_KEY'              : '',
    'DEFAULT_TEMPLATE'              : '',
    'DEFAULT_TEMPLATE_NO_BUTTON'    : '',
    'AUTOMATION_TEMPLATE'           : '',
    'SLACK_APP_ID'                  : '',
    'SLACK_CLIENT_ID'               : '',
    'SLACK_CLIENT_SECRET'           : '',
    'SLACK_SIGNING_SECRET'          : '',
    'SLACK_VERIFICATION_TOKEN'      : '',
    'SLACK_BOT_TOKEN'               : '',
    'AWS_ACCESS_KEY_ID'             : '',
    'AWS_SECRET_ACCESS_KEY'         : '',
    'GPT_API_KEY'                   : '',

    # system generated
    'DB_PASS'             : '',
    'POSTGRES_PASSWORD'   : '',
    'SECRETS_KEY'         : ''
}


CLIENT_VARS = {

    # retrieved from user input
    'REACT_APP_SERVER_URL'  : '',
    'REACT_APP_CLIENT_URL'  : '',
    'LETSENCRYPT_EMAIL'     : '',
    'LETSENCRYPT_HOST'      : '',
    'VIRTUAL_HOST'          : ''
}




@app.command()
def setup() -> None:

    """ 
    Setup and configure env's for Client and Server
    """

    # rename each .env file
    env_client_old.rename(env_client)
    env_server_old.rename(env_server)

    # set defaults
    ready = False
    admin_confirmed = False
    domains_confirmed = False
    headers = {'content-type': 'application/json'}

    # generate keys and passwords
    db_password = secrets.token_urlsafe(12)
    random_key = secrets.token_bytes(32)
    secret_key = base64.urlsafe_b64encode(random_key).decode('utf-8')
    
    # update SERVER vars
    SERVER_VARS['DB_PASS']           = db_password
    SERVER_VARS['POSTGRES_PASSWORD'] = db_password
    SERVER_VARS['SECRETS_KEY']       = secret_key

    
    # get license key and API data
    while not ready:

        # ask for license key
        license_key = typer.prompt(
            text='  Enter your license key', 
            hide_input=True
        )

        # get all API data
        api_data = requests.post(
            url=f'{cursion_root}/v1/auth/account/license', 
            headers=headers,
            data=json.dump({'license_key': license_key})
        ).json()

        # update all api data in SERVER vars
        if api_data.get('success'):
            
            data = api_data.get('data')
            for key in data:
                if SERVER_VARS.get(key):
                    SERVER_VARS[key] = data[key]

            # add license_key to SERVER vars
            SERVER_VARS['LICENSE_KEY'] = license_key

            rprint(
                '[green bold]' +
                u'\u2714' +
                '[/green bold]'+
                f" License is verified"
            )

            # set ready -> True
            ready = True
    
        else:
            # incorrect key
            rprint(
                '[red bold]' +
                u'\u2718' +
                '[/red bold]' +
                ' incorrect license key'
            )

   
    # ask for admin email
    admin_email = typer.prompt(
        text='  Enter an admin email address', 
    )

    # get admin password inputs
    while not admin_confirmed:

        # ask for admin password
        pass_1 = typer.prompt(
            text='  Create an admin password', 
            hide_input=True
        )

        # confirm admin pass
        pass_2 = typer.prompt(
            text='  Confirm admin password', 
            hide_input=True
        )

        # check password
        admin_confirmed = pass_1 == pass_2
        
        # update admin creds for SERVER & CLIENT vars
        if admin_confirmed:
            SERVER_VARS['ADMIN_USER'] = 'admin'
            SERVER_VARS['ADMIN_EMAIL'] = admin_email
            SERVER_VARS['ADMIN_PASSWORD'] = pass_1
            SERVER_VARS['DEFAULT_EMAIL'] = admin_email
            SERVER_VARS['LETSENCRYPT_EMAIL'] = admin_email
            CLIENT_VARS['LETSENCRYPT_EMAIL'] = admin_email

            rprint(
                '[green bold]' +
                u'\u2714' +
                '[/green bold]'+
                f' Credentials updated:\n' +
                f'  username    : admin\n' +
                f'  email       : {admin_email}\n' +
                f'  password    : •••••••••••••••••••••••••••'
            )

        if not admin_confirmed:
            # incorrect key
            rprint(
                '[red bold]' +
                u'\u2718' +
                '[/red bold]' +
                ' passwords do not match'
            )


    # get domain name inputs
    while not domains_confirmed:

        # ask for server domain name
        server_domain = typer.prompt(
            text='  Enter your Server domain (i.e. api.example.com)', 
        )
        
        # ask for client domain name
        client_domain = typer.prompt(
            text='  Enter your Client domain (i.e. app.example.com)', 
        )

        # clean urls
        server_domain = server_domain.replace('/','')
        client_domain = client_domain.replace('/','')
        server_url = f'https://{server_domain}'
        client_url = f'https://{client_domain}'

        # ask for CLIENT url change request
        domains_confirmed = typer.confirm(
            text=f'  Does this look correct?  ({server_url})  ({client_url}) ', 
        )

        # check if correct
        if domains_confirmed:

            # update SERVER vars
            SERVER_VARS['CLIENT_URL_ROOT']  = client_url
            SERVER_VARS['API_URL_ROOT']     = server_url
            SERVER_VARS['LETSENCRYPT_HOST'] = server_domain
            SERVER_VARS['VIRTUAL_HOST']     = server_domain
            
            # update CLIENT vars
            CLIENT_VARS['REACT_APP_SERVER_URL'] = server_url
            CLIENT_VARS['REACT_APP_CLIENT_URL'] = client_url
            CLIENT_VARS['LETSENCRYPT_HOST']     = client_domain
            CLIENT_VARS['VIRTUAL_HOST']         = client_domain

            rprint(
                '[green bold]' +
                u'\u2714' +
                '[/green bold]'+
                f" Domains updated"
            )


    # update CLIENT .env with new data
    update_env(str(env_client), CLIENT_VARS)

    # update SERVER .env with new data
    update_env(str(env_server), SERVER_VARS)
    
    # print response
    rprint(
        '[green bold]' +
        u'\u2714' +
        '[/green bold]'+
        f" Configuration complete!"
    )
    
    return None




def update_env(env_path: str, variables: dict) -> None:

    """
    Updates or adds variables in passed .env file
    """

    # set default
    updated_lines = []

    # Read the .env file and update the variable
    with open(env_path, 'r') as file:

        # iterate through each key in variables
        for key in variables:
            
            # set default
            var_found = False

            # iterate through each line
            for line in file:

                # check if the line starts with the variable key
                if line.startswith(f'{key}='):
                    
                    # add new line with updated value
                    updated_lines.append(f'{key}={variables[key]}\n')
                    var_found = True
                
                # add line as it is
                elif line not in updated_lines:
                    updated_lines.append(line)
    
            # Add the variable if it was not found
            if not var_found:
                updated_lines.append(f'{key}={variables[key]}\n')
        
    # Write the updated content back to the file
    with open(env_path, 'w') as file:
        file.writelines(updated_lines)




## --- Installer entry point --- ##
if __name__ == '__main__':
    app()