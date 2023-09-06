use std::ops::{Deref, DerefMut};
use std::sync::Arc;

use crate::core::config::Config;
use crate::core::engine::Engine as DaggerEngine;
use crate::core::graphql_client::DefaultGraphQLClient;

use crate::errors::ConnectError;
use crate::gen::Query;
use crate::logging::StdLogger;
use crate::querybuilder::query;

#[derive(Clone)]
pub struct Dagger(Arc<Query>);

impl Deref for Dagger {
    type Target = Arc<Query>;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Dagger {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl From<Arc<Query>> for Dagger {
    fn from(value: Arc<Query>) -> Self {
        Self(value)
    }
}

pub async fn connect() -> Result<Dagger, ConnectError> {
    let cfg = Config::new(None, None, None, None, Some(Arc::new(StdLogger::default())));

    connect_opts(cfg).await
}

pub async fn connect_opts(cfg: Config) -> Result<Dagger, ConnectError> {
    let (conn, proc) = DaggerEngine::new()
        .start(&cfg)
        .await
        .map_err(ConnectError::FailedToConnect)?;

    Ok(Arc::new(Query {
        proc: proc.map(|p| Arc::new(p)),
        selection: query(),
        graphql_client: Arc::new(DefaultGraphQLClient::new(&conn)),
    })
    .into())
}

// Conn will automatically close on drop of proc

#[cfg(test)]
mod test {
    use super::connect;

    #[tokio::test]
    async fn test_connect() {
        let _ = connect().await.unwrap();
    }
}
