bash -l -c "bundle exec rails db:environment:set RAILS_ENV=${RAILS_ENV}"
bash -l -c "bundle exec rails db:migrate"
bash -l -c "bundle exec rake geoblacklight:server['-b 0.0.0.0']"

