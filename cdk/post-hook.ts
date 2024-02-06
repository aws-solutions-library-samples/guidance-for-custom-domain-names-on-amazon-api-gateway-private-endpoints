import * as url from 'url';
import * as path from 'path';
import stringHash = require('string-hash');
import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import * as yaml from 'js-yaml';
import { parse } from 'ts-command-line-args';
import { proxyDomain } from './bin/Main';

/* eslint-disable @typescript-eslint/no-explicit-any */

type IArguments = {
    region: string;
    destinationPath: string;
    stackOutputs: string;
    proxyFilePath: string;
};

async function Run() {
    const args = parse<IArguments>({
        region: { type: String },
        destinationPath: { type: String },
        stackOutputs: { type: String },
        proxyFilePath: { type: String },
    });

    const yamlOutput: any = yaml.load(readFileSync(path.join(args.proxyFilePath), 'utf8'));
    const proxyDomains: proxyDomain[] = yamlOutput?.APIS as proxyDomain[];

    GenerateOutputsFile(args, proxyDomains);
}
const GenerateOutputsFile = (props: IArguments, proxyDomains: proxyDomain[]): void => {
    const apiGatewayVPCInterfaceEndpointId: any = (JSON.parse(props.stackOutputs) as any)?.find(
        (output: any) => output.OutputKey === 'apigatewayvpceid',
    )?.OutputValue;

    const outputObj: any = {};
    outputObj.STACK_OUTPUTS = JSON.parse(props.stackOutputs);

    const arrPolicyMappings: any = {};
    proxyDomains.forEach((item) => {
        const api_gateway_id = item.PRIVATE_API_URL.split('https://')[1].split('.execute-api')[0];

        if (api_gateway_id in arrPolicyMappings) {
            arrPolicyMappings[api_gateway_id].Statement.push(generateSpecificPolicyStatement(props, item));
        } else {
            arrPolicyMappings[api_gateway_id] = {
                Version: '2012-10-17',
                Statement: [
                    {
                        Sid: 'reverse-proxy-deny',
                        Effect: 'Deny',
                        Principal: '*',
                        Action: 'execute-api:Invoke',
                        Resource: generateResources(props, item, 'deny'),
                        Condition: {
                            StringNotEquals: {
                                'aws:SourceVpce': `${apiGatewayVPCInterfaceEndpointId}`,
                            },
                        },
                    },
                    generateSpecificPolicyStatement(props, item),
                ],
            };
        }
    });

    outputObj.API_RESOURCE_POLICY_MAPPING = arrPolicyMappings;

    if (props.destinationPath.indexOf('\0') !== -1) {
        return process.exit(1);
    }
    mkdirSync(path.parse(props.destinationPath).dir, { recursive: true });
    writeFileSync(props.destinationPath, JSON.stringify(outputObj, null, 2));

    console.log(`
  ########################## Deployment Complete ###################################

  ------> outputs.json file saved at location ${path.join(props.destinationPath)}

  ##################################################################################
  
  `);
};

const generateSpecificPolicyStatement = (props: IArguments, item: proxyDomain) => {
    return {
        Sid: `reverse-proxy-allow-${stringHash(item.PRIVATE_API_URL)}`,
        Effect: 'Allow',
        Principal: '*',
        Action: 'execute-api:Invoke',
        Resource: generateResources(props, item, 'allow'),
        Condition: {
            StringEquals: {
                'aws:Referer': item.CUSTOM_DOMAIN_URL,
            },
        },
    };
};

const generateResources = (props: IArguments, item: proxyDomain, policyType: 'deny' | 'allow') => {
    const resources: string[] = [];
    const pathSplit = new url.URL(item.PRIVATE_API_URL).pathname.split('/');
    const stage = pathSplit[1];
    let endPath = '';
    for (let i = 2; i < pathSplit.length; i++) {
        endPath += `/${pathSplit[i]}`;
    }
    const resourcePath = endPath.substring(1) || '*';
    if (policyType === 'allow') {
        if (item.VERBS) {
            item.VERBS.forEach((verb) => {
                resources.push(`execute-api:/${stage}/${verb.toUpperCase()}/${resourcePath}`);
            });
        } else {
            resources.push(`execute-api:/${stage}/*/${resourcePath}`);
        }
    } else {
        resources.push(`execute-api:/*/*/*`);
    }

    return resources;
};

(async function () {
    await Run();
})().catch((e) => {
    console.error(e);
    process.exit(1);
});
