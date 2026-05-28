///
/// NOVA Cloud CLI — Config Store
///
/// Stores auth tokens, current app, API URL in ~/.nova-cloud/config.json
///

import Conf from 'conf';

let _config: Conf | null = null;

export function getConfig(): Conf {
  if (!_config) {
    _config = new Conf({
      projectName: 'nova-cloud',
      schema: {
        token: { type: 'string', default: '' },
        api_url: { type: 'string', default: 'http://localhost:4000' },
        current_app: { type: 'string', default: '' },
        user_email: { type: 'string', default: '' },
        user_id: { type: 'string', default: '' },
        org_id: { type: 'string', default: '' },
      },
    });
  }
  return _config;
}
