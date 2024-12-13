#!/usr/bin/env python3
from pathlib import Path
from rich import print as rprint
import typer, os, json, time, shutil, secrets, base64, requests, sys


# High Level Configs

app = typer.Typer()
local = '/home/cursion/app/selfhost' # testing path -> f'{str(Path.home())"/documents/coding/cursion/selfhost'
env_dir = Path(f'{local}/env')
env_client = Path(f'{local}/env/.client.env')
env_server = Path(f'{local}/env/.server.env')
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

    # set defaults
    verified = False
    admin_confirmed = False
    domains_confirmed = False
    headers = {'content-type': 'application/json'}

    # generate keys and passwords
    db_password = secrets.token_urlsafe(12)
    random_key = secrets.token_bytes(32)
    secret_key = base64.urlsafe_b64encode(random_key).decode('utf-8')
    
    # update SERVER vars
    SERVER_VARS['DB_PASS']           = 'supersecretpassword'
    SERVER_VARS['POSTGRES_PASSWORD'] = 'supersecretpassword'
    SERVER_VARS['SECRETS_KEY']       = secret_key

    
    # get license key and API data
    while not verified:

        # ask for license key
        license_key = typer.prompt(
            text='  Enter your license key', 
            hide_input=True
        )

        # get all API data
        api_data = requests.post(
            url=f'{cursion_root}/v1/auth/account/license', 
            headers=headers,
            data=json.dumps({'license_key': license_key})
        ).json()

        # update all api data in SERVER vars
        if api_data.get('success'):
            
            data = api_data.get('data')
            for key in data:
                if key in SERVER_VARS:
                    SERVER_VARS[key] = data[key]

            # add license_key to SERVER vars
            SERVER_VARS['LICENSE_KEY'] = license_key

            rprint(
                '[green bold]' +
                '[✓]' +
                '[/green bold]'+
                f' License is verified'
            )

            # set verified -> True
            verified = True
    
        else:
            # incorrect key
            rprint(
                '[red bold]' +
                '[✘]' +
                '[/red bold]' +
                ' incorrect license key'
            )
   

    # ask for admin email
    admin_email = typer.prompt(
        text='  Enter an admin email address'
    )
    
    # update email and add username
    SERVER_VARS['ADMIN_USER'] = 'admin'
    SERVER_VARS['ADMIN_EMAIL'] = admin_email
    SERVER_VARS['DEFAULT_EMAIL'] = admin_email
    SERVER_VARS['LETSENCRYPT_EMAIL'] = admin_email
    CLIENT_VARS['LETSENCRYPT_EMAIL'] = admin_email


    # get admin password inputs
    while not admin_confirmed:

        # flush prompts
        sys.stdout.flush()

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
            SERVER_VARS['ADMIN_PASS'] = pass_1

            rprint(
                '[green bold]' +
                '[✓]' +
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
                '[✘]' +
                '[/red bold]' +
                ' passwords do not match'
            )


    # get domain name inputs
    while not domains_confirmed:

        # ask for server domain name
        server_domain = typer.prompt(
            text='  Enter your Server domain (e.g. api.example.com)', 
        )
        
        # ask for client domain name
        client_domain = typer.prompt(
            text='  Enter your Client domain (e.g. app.example.com)', 
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
                '[✓]' +
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
        '[✓]' +
        '[/green bold]'+
        f" Configuration complete!"
    )
    
    return




def update_env(env_path: str, variables: dict) -> None:
    """
    Updates or adds variables in the passed .env 
    file while preserving unchanged lines.
    """
    # Read the current .env file content into memory
    with open(env_path, 'r') as file:
        lines = file.readlines()

    # Track variables that have been updated or added
    updated_keys = set()

    # Prepare the updated content
    updated_lines = []

    for line in lines:
        # Check if the line contains a key-value pair
        if '=' in line and not line.startswith('#'):
            key, _ = line.strip().split('=', 1)
            if key in variables:
                # Update the variable
                updated_lines.append(f'{key}={variables[key]}\n')
                updated_keys.add(key)
            else:
                # Preserve the existing variable
                updated_lines.append(line)
        else:
            # Preserve comments and empty lines
            updated_lines.append(line)

    # Add any new variables that were not in the original file
    for key, value in variables.items():
        if key not in updated_keys:
            updated_lines.append(f'{key}={value}\n')

    # Write the updated content back to the .env file
    with open(env_path, 'w') as file:
        file.writelines(updated_lines)





## --- Installer entry point --- ##
if __name__ == '__main__':
    app()