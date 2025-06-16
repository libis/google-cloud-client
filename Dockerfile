FROM ruby:3.1.4
# A minimal Dockerfile based on Ruby (2.3, 2.4, 2.5 or 2.6) Dockerfile (regular, slim or alpine) with Node.js 10 LTS (Dubnium) installed.
#FROM timbru31/ruby-node  

# Install gems
ENV APP_HOME=/app
ENV HOME=/root

RUN cp /usr/share/zoneinfo/CET /etc/localtime 

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev libaio1 unzip ffmpeg

RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && apt-get update -y && apt-get install google-cloud-cli -y

# RUN gcloud init
# RUN gcloud auth print-access-token
# RUN gcloud auth application-default login
# RUN gcloud auth application-default set-quota-project wired-coder-368209

RUN mkdir $APP_HOME
WORKDIR $APP_HOME
COPY Gemfile ./
RUN gem install bundler
RUN bundle install

WORKDIR $APP_HOME
COPY src ./src
RUN ls -l /app/src/

