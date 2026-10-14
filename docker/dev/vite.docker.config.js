// Vite configuration for the Docker development server.
//
// The repository's own vite.config.js is imported as-is and only the dev server
// block is replaced, because inside a container:
//
//   - the server has to listen on 0.0.0.0 (0.0.0.0 alone is what Docker can
//     forward), while
//   - the URL written into public/hot and the HMR endpoint used by the browser
//     have to be the published address on the host, not the container's own.
//
//   docker compose exec vite pnpm run dev -- --config docker/dev/vite.docker.config.js
//
// VITE_HOST/VITE_PORT come from docker/.env.dev.

import base from '../../vite.config.js';

const port = Number(process.env.VITE_PORT ?? 5173);
const host = process.env.VITE_HOST ?? 'localhost';

export default {
    ...base,
    server: {
        host: '0.0.0.0',
        port,
        strictPort: true,
        origin: `http://${host}:${port}`,
        hmr: {
            host,
            port,
            protocol: 'ws',
        },
    },
};
