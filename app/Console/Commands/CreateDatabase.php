<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class CreateDatabase extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'db:create';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Creates the database for the current APP_ENV';

    /**
     * Create a new command instance.
     *
     * @return void
     */
    public function __construct()
    {
        parent::__construct();
    }

    /**
     * Execute the console command.
     *
     * @return mixed
     */
    public function handle()
    {
        $database_connection = DB::connection();
        $database_config = $database_connection->getConfig();
        $pdo = $database_connection->getPdo();
        $database_name = $database_config['database'];
        $database_charset = $database_config['charset'];
        $database_collation = $database_config['collation'];

        try {
            $pdo->exec(sprintf(
                'CREATE DATABASE IF NOT EXISTS %s CHARACTER SET %s COLLATE %s;',
                $database_name,
                $database_charset,
                $database_collation
            ));

            $this->info(
                sprintf('Successfully created %s database', $database_name)
            );
        } catch (PDOException $exception) {
            $this->error(
                sprintf(
                    'Failed to create %s database, %s',
                    $database_name,
                    $exception->getMessage()
                )
            );
        }
    }
}
