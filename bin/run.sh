rand_mod=$(expr $RANDOM % 5)
if [ $rand_mod -eq 0 ]; then
    echo "Starting divisible by five app"
else
    echo "Crashing non-divisible by five app";
    exit 1
fi

python manage.py cf_startup
gunicorn --access-logfile - --error-logfile - --log-level info --timeout 300 -k gevent -w 9 webservices.rest:app
