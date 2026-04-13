// Configuration for Production Tests
require('dotenv').config();

module.exports = {
    baseURL: process.env.PROD_API_URL || 'https://www.desinomads.com',
    credentials: {
        email: process.env.PROD_TEST_EMAIL || 'it@edgestone.in',
        password: process.env.PROD_TEST_PASSWORD || 'i@edgestone123'
    }
};
