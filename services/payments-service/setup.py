from setuptools import setup, find_packages

setup(
    name='payments-service',
    version='1.0.0',
    packages=find_packages(),
    install_requires=[
        'Flask==2.3.0',
        'python-dotenv==1.0.0',
        'pika==1.3.1',
        'redis==5.0.0',
        'pytest==7.4.0',
        'pytest-cov==4.1.0',
        'pytest-mock==3.11.1',
    ],
    python_requires='>=3.8',
)